#!/usr/bin/env python3
"""
Print a photo to a Peripage A6 (BLE firmware) from macOS.

This version sends the image in row blocks of up to 256 rows each, with
a fresh GS v 0 header per block. Some Peripage firmwares mis-render single
giant blocks but handle multiple smaller blocks correctly.

Also saves a preview of exactly what's being sent to /tmp/peripage_preview.png
so you can visually verify the image processing is correct independent of
the printer's behavior. Use --no-print to generate the preview without
connecting to the printer.

Usage:
    python print_photo.py path/to/photo.jpg
    python print_photo.py path/to/photo.heic
    python print_photo.py photo.jpg --no-print          # just make the preview
    python print_photo.py photo.jpg --contrast 1.3
    python print_photo.py photo.jpg --top 40 --bottom 120
"""

import argparse
import asyncio
import sys
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps
from bleak import BleakClient, BleakScanner

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass

# --- BLE config ---
PRINTER_NAME_PREFIX = "PeriPage"
WRITE_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"

# --- Protocol ---
# Calibrated against Bryan's printer with the test pattern in webui.py:
# 576 dots fills the full 57mm paper width. (Standard A6 docs say 384 but
# this unit is a 576-dot variant.)
PRINT_WIDTH_PX = 576
ROW_BYTES = PRINT_WIDTH_PX // 8       # 72 bytes per row, 1bpp MSB-first
# 96 bytes was the working BLE chunk size from before the width bump. Doesn't
# need to align with ROW_BYTES — the printer reassembles the byte stream.
CHUNK_SIZE = 96
ROWS_PER_BLOCK = 256                  # send image as multiple GS v 0 blocks

# --- New protocol (post-firmware-update) ---
# Captured 2026-06-07 from the official Peripage iOS app via PacketLogger
# on a PeriPage+064E_BLE unit. The old CMD_RESET=10 11 FF FE 01 no longer
# triggers a print; the firmware now expects this START/END pair plus a
# raw zero-byte leading silence (NOT ESC J n) and one big GS v 0 block.
CMD_START_A = bytes.fromhex("10ff100001")    # session init
CMD_START_B = bytes.fromhex("10fffe01")      # ready / clear buffer
CMD_END     = bytes.fromhex("10fffe45")      # commit and print
LEADING_SILENCE_BYTES = 1024                 # raw 0x00 before the raster
TRAILING_FEED_PX = 96                        # fixed ESC J 96 after raster


async def find_printer(timeout: float = 8.0) -> str | None:
    print(f"Scanning for '{PRINTER_NAME_PREFIX}' devices...")
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    for addr, (device, adv) in devices.items():
        name = device.name or adv.local_name or ""
        if PRINTER_NAME_PREFIX.lower() in name.lower():
            print(f"  Found {name} @ {addr}")
            return addr
    print("  No Peripage found.")
    return None


def prepare_image(path: Path, brightness: float, contrast: float) -> Image.Image:
    """Load, EXIF-correct, rotate landscape→portrait, scale, dither to 1-bit."""
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)
    print(f"  Source after EXIF: {img.size} (mode={img.mode})")

    if img.width > img.height:
        img = img.rotate(90, expand=True)
        print(f"  Rotated 90° CCW (was landscape): {img.size}")
    else:
        print(f"  No rotation needed (portrait or square): {img.size}")

    img = img.convert("L")

    if brightness != 1.0:
        img = ImageEnhance.Brightness(img).enhance(brightness)
    if contrast != 1.0:
        img = ImageEnhance.Contrast(img).enhance(contrast)

    new_height = int(img.height * (PRINT_WIDTH_PX / img.width))
    img = img.resize((PRINT_WIDTH_PX, new_height), Image.LANCZOS)
    print(f"  Scaled to: {img.size}")

    img = img.convert("1", dither=Image.FLOYDSTEINBERG)
    return img


def encode_image_to_bytes(img: Image.Image) -> bytes:
    """Pack 1-bit image to raster bytes. PIL '1' mode: bit=1 means white pixel.
    Peripage wants bit=1 to mean BLACK (fire heating element), so we invert."""
    width, height = img.size
    assert width == PRINT_WIDTH_PX, f"width is {width}, expected {PRINT_WIDTH_PX}"
    raw = img.tobytes()
    expected = ROW_BYTES * height
    assert len(raw) == expected, f"got {len(raw)} bytes, expected {expected}"
    return bytes(b ^ 0xFF for b in raw)


def build_payload(image_bytes: bytes, height: int,
                  leading_feed: int = 0, trailing_feed: int = 0) -> bytes:
    """Build the byte stream for the post-update firmware:

      CMD_START_A | CMD_START_B | <1024 zero bytes> | GS v 0 raster | ESC J 96 | CMD_END

    The leading_feed/trailing_feed args are kept for CLI compatibility but
    ignored — the new firmware uses a fixed leading silence (1024 zero
    bytes, not ESC J) and a fixed 96-pixel trailing feed.
    """
    xL, xH = ROW_BYTES & 0xFF, (ROW_BYTES >> 8) & 0xFF
    yL, yH = height & 0xFF, (height >> 8) & 0xFF
    parts = [
        CMD_START_A,
        CMD_START_B,
        b"\x00" * LEADING_SILENCE_BYTES,
        bytes([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]),
        image_bytes,
        bytes([0x1B, 0x4A, TRAILING_FEED_PX]),
        CMD_END,
    ]
    print(f"  Image: 1 raster block of {height} rows (no split).")
    return b"".join(parts)


async def send_payload(client: BleakClient, payload: bytes) -> None:
    total = len(payload)
    chunks = (total + CHUNK_SIZE - 1) // CHUNK_SIZE
    print(f"  Sending {total:,} bytes in {chunks} chunks...")
    sent = 0
    for i in range(0, total, CHUNK_SIZE):
        chunk = payload[i:i + CHUNK_SIZE]
        await client.write_gatt_char(WRITE_UUID, chunk, response=False)
        sent += len(chunk)
        await asyncio.sleep(0.015)
        if sent % (CHUNK_SIZE * 50) == 0 or sent == total:
            print(f"    {sent:,}/{total:,} ({100*sent/total:.0f}%)")
    print("  All chunks sent.")


async def print_photo(image_path: Path, brightness: float, contrast: float,
                      leading_feed: int, trailing_feed: int,
                      preview_path: Path, no_print: bool) -> None:
    print(f"Preparing image: {image_path}")
    img = prepare_image(image_path, brightness, contrast)

    img.save(preview_path)
    print(f"  Preview saved: {preview_path}")

    image_bytes = encode_image_to_bytes(img)
    payload = build_payload(image_bytes, img.height, leading_feed, trailing_feed)
    print(f"  Payload: {len(payload):,} bytes "
          f"(image {img.height} rows, top {leading_feed}px, bottom {trailing_feed}px)")

    if no_print:
        print(f"\n--no-print: skipping BLE. Open the preview to verify:")
        print(f"  open {preview_path}")
        return

    address = await find_printer()
    if not address:
        print("\nMake sure the printer is on and not connected to your phone.")
        sys.exit(1)

    print(f"\nConnecting to {address}...")
    async with BleakClient(address) as client:
        print(f"  Connected. MTU: {client.mtu_size}")
        await send_payload(client, payload)
        print("  Waiting 3s for buffer drain...")
        await asyncio.sleep(3.0)
    print("\nDone.")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Print a photo to a Peripage A6 over BLE.")
    p.add_argument("image", type=Path)
    p.add_argument("--brightness", type=float, default=1.0)
    p.add_argument("--contrast", type=float, default=1.2)
    p.add_argument("--top", type=int, default=40, help="Top margin in pixels")
    p.add_argument("--bottom", type=int, default=120, help="Bottom margin in pixels")
    p.add_argument("--preview", type=Path, default=Path("/tmp/peripage_preview.png"),
                   help="Where to save preview (default /tmp/peripage_preview.png)")
    p.add_argument("--no-print", action="store_true",
                   help="Save preview only, don't connect to printer")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if not args.image.exists():
        print(f"File not found: {args.image}")
        sys.exit(1)
    asyncio.run(print_photo(
        image_path=args.image,
        brightness=args.brightness,
        contrast=args.contrast,
        leading_feed=args.top,
        trailing_feed=args.bottom,
        preview_path=args.preview,
        no_print=args.no_print,
    ))


if __name__ == "__main__":
    main()
