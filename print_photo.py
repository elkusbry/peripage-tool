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

CMD_RESET = bytes.fromhex("1011fffe01")


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
                  leading_feed: int, trailing_feed: int) -> bytes:
    """Build the full byte stream: reset, top feed, image blocks, bottom feed, reset."""
    parts = [CMD_RESET]

    if leading_feed > 0:
        feed_left = leading_feed
        while feed_left > 0:
            n = min(feed_left, 255)
            parts.append(bytes([0x1B, 0x4A, n]))
            feed_left -= n

    # Send image as multiple GS v 0 blocks of <= ROWS_PER_BLOCK rows each.
    rows_sent = 0
    blocks = 0
    while rows_sent < height:
        rows_in_block = min(ROWS_PER_BLOCK, height - rows_sent)
        xL, xH = ROW_BYTES & 0xFF, (ROW_BYTES >> 8) & 0xFF
        yL, yH = rows_in_block & 0xFF, (rows_in_block >> 8) & 0xFF
        parts.append(bytes([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]))

        start = rows_sent * ROW_BYTES
        end = start + (rows_in_block * ROW_BYTES)
        parts.append(image_bytes[start:end])

        rows_sent += rows_in_block
        blocks += 1
    print(f"  Image split into {blocks} block(s) of <= {ROWS_PER_BLOCK} rows.")

    if trailing_feed > 0:
        feed_left = trailing_feed
        while feed_left > 0:
            n = min(feed_left, 255)
            parts.append(bytes([0x1B, 0x4A, n]))
            feed_left -= n

    parts.append(CMD_RESET)
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
