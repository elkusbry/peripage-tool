#!/usr/bin/env python3
"""
Generate the Peripage app icon — a 1024x1024 PNG showing a Floyd-Steinberg
dithered sun-and-mountains scene. The icon is the app's own output style:
white paper, black thermal-fire pixels, no anti-aliasing.

The motif is a stylized sunrise over a mountain — chosen because:
  - it's a classic photo subject (the app prints photos)
  - the smooth radial gradient + slope produces a *visible* dither pattern
    that telegraphs "this is a 1-bit thermal print"

Run: python fixtures/make_app_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "ios" / "Peripage" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
OUT = OUT_DIR / "icon_1024.png"

SIZE = 1024
# We render at 4x then downsample so the final dither is crisp at 1024.
RENDER = SIZE


def make_scene() -> Image.Image:
    """Draw a smooth grayscale scene; the dither happens after."""
    img = Image.new("L", (RENDER, RENDER), 255)  # white paper
    px = img.load()

    cx, cy = RENDER // 2, int(RENDER * 0.42)   # sun center, slightly above mid
    sun_radius = int(RENDER * 0.22)
    halo_radius = int(RENDER * 0.46)

    # Radial halo around the sun: white center, getting darker toward halo edge.
    for y in range(RENDER):
        for x in range(RENDER):
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= sun_radius:
                # solid black sun
                px[x, y] = 0
            elif d <= halo_radius:
                # smooth ramp from black at sun edge to white at halo edge.
                # Squared falloff makes the dither look organic.
                t = (d - sun_radius) / (halo_radius - sun_radius)
                # white = 255, black = 0; we want white as t→1
                val = int(255 * (t ** 1.4))
                px[x, y] = max(px[x, y] - (255 - val), val)

    # Mountain silhouette across the lower third — solid black, hard edge.
    horizon_y = int(RENDER * 0.66)
    peaks = [
        (int(RENDER * 0.00), horizon_y + 40),
        (int(RENDER * 0.15), int(RENDER * 0.62)),
        (int(RENDER * 0.30), int(RENDER * 0.78)),
        (int(RENDER * 0.50), int(RENDER * 0.55)),  # tallest peak
        (int(RENDER * 0.68), int(RENDER * 0.74)),
        (int(RENDER * 0.85), int(RENDER * 0.65)),
        (int(RENDER * 1.00), horizon_y + 30),
        (RENDER, RENDER),
        (0, RENDER),
    ]
    draw = ImageDraw.Draw(img)
    draw.polygon(peaks, fill=0)

    # A thin "ground line" slightly above the mountain base to give the
    # dither pattern a clean horizontal reference.
    draw.rectangle([(0, RENDER - 4), (RENDER, RENDER)], fill=0)

    # Light blur so the dither has gradient material to chew on
    img = img.filter(ImageFilter.GaussianBlur(radius=1.5))
    return img


def dither_and_save(img: Image.Image) -> None:
    # Floyd-Steinberg via PIL's "1" mode conversion.
    bw = img.convert("1", dither=Image.FLOYDSTEINBERG)

    # Convert back to RGB on a pure white background — iOS icons must
    # have NO transparency, and we want a true white "paper" background.
    out = Image.new("RGB", bw.size, (255, 255, 255))
    out.paste(bw.convert("RGB"))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out.save(OUT, "PNG", optimize=True)
    print(f"Wrote {OUT} ({out.size[0]}×{out.size[1]})")


def main() -> None:
    print("Generating Peripage app icon…")
    scene = make_scene()
    dither_and_save(scene)


if __name__ == "__main__":
    main()
