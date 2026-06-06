#!/usr/bin/env python3
"""
Generate Swift test fixtures from the working Python tool.

For each source image, this writes:
  - the source PNG (also used by Swift to drive its own pipeline)
  - the expected raster bytes (after prepare_image + encode_image_to_bytes)
  - the expected payload bytes (after build_payload with known margins)

Run: python fixtures/generate_fixtures.py
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from PIL import Image

# Import from the working tool — single source of truth for the protocol.
from print_photo import (
    prepare_image, encode_image_to_bytes, build_payload,
    PRINT_WIDTH_PX, ROW_BYTES,
)

OUT = REPO_ROOT / "ios" / "PeripageTests" / "Fixtures"
OUT.mkdir(parents=True, exist_ok=True)


def make_flat_gray(size=(64, 64), value=128) -> Path:
    p = OUT / "flat_gray_64x64.png"
    Image.new("L", size, value).save(p)
    return p


def make_landscape(size=(400, 300)) -> Path:
    p = OUT / "landscape_400x300.png"
    img = Image.new("L", size, 200)
    # diagonal gradient so dither has structure
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = (x + y) % 256
    img.save(p)
    return p


def make_portrait(size=(300, 400)) -> Path:
    p = OUT / "portrait_300x400.png"
    img = Image.new("L", size, 200)
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = (x + y) % 256
    img.save(p)
    return p


def dump(image_path: Path, name: str, top: int = 40, bottom: int = 120) -> None:
    img = prepare_image(image_path, brightness=1.0, contrast=1.2)
    raster = encode_image_to_bytes(img)
    payload = build_payload(raster, img.height, leading_feed=top, trailing_feed=bottom)
    (OUT / f"{name}_raster.bin").write_bytes(raster)
    (OUT / f"{name}_payload_t{top}_b{bottom}.bin").write_bytes(payload)
    (OUT / f"{name}_meta.txt").write_text(
        f"width={img.width}\nheight={img.height}\n"
        f"raster_len={len(raster)}\npayload_len={len(payload)}\n"
        f"row_bytes={ROW_BYTES}\nprint_width_px={PRINT_WIDTH_PX}\n"
    )
    print(f"  {name}: {img.size}, raster={len(raster)}, payload={len(payload)}")


def main() -> None:
    print("Generating fixtures…")
    dump(make_flat_gray(), "flat_gray")
    dump(make_landscape(), "landscape")
    dump(make_portrait(), "portrait")
    print(f"Wrote fixtures to {OUT}")


if __name__ == "__main__":
    main()
