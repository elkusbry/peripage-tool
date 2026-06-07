#!/usr/bin/env python3
"""
Web UI for orienting and printing photos to a Peripage A6.

Run from a Terminal that has Bluetooth permission:
    venv/bin/python webui.py
Then open http://localhost:8080
(Port 5000 is stolen by macOS AirPlay Receiver.)

Single-user, in-memory. State is a single "current image" plus a transform
(rotation, flips, brightness, contrast). The preview shows exactly what the
printer will see — 384px wide, dithered to 1bpp.
"""

import asyncio
import io
import threading
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps
from flask import Flask, jsonify, render_template_string, request, send_file

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass

from print_photo import (
    find_printer,
    send_payload,
    CMD_START_A,
    CMD_START_B,
    CMD_END,
    LEADING_SILENCE_BYTES,
    TRAILING_FEED_PX,
)
from bleak import BleakClient


@dataclass
class State:
    original: Image.Image | None = None
    filename: str = ""
    rotation: int = 0           # 0, 90, 180, 270 (CW degrees)
    flip_h: bool = False
    flip_v: bool = False
    brightness: float = 1.0
    contrast: float = 1.2
    top: int = 40
    bottom: int = 40
    # Crop rect in normalized 0..1 coords, applied AFTER rotate/flip.
    # None means no crop (full image).
    crop: tuple[float, float, float, float] | None = None
    # Print head width in dots. Your printer is 576-dot (calibrated by test
    # pattern: 576 dots filled the full 57mm paper).
    width_dots: int = 576
    lock: threading.Lock = field(default_factory=threading.Lock)


state = State()
app = Flask(__name__)


def render_oriented(s: State) -> Image.Image:
    """Apply EXIF + rotate + flip only. Used as the crop-editor source."""
    img = s.original
    img = ImageOps.exif_transpose(img)
    if s.rotation:
        img = img.rotate(-s.rotation, expand=True)   # negative = CW
    if s.flip_h:
        img = ImageOps.mirror(img)
    if s.flip_v:
        img = ImageOps.flip(img)
    return img


def render_for_print(s: State) -> Image.Image:
    """Apply current transform → dithered 1-bit image at PRINT_WIDTH_PX."""
    img = render_oriented(s)

    if s.crop:
        x, y, w, h = s.crop
        W, H = img.size
        box = (
            max(0, int(x * W)),
            max(0, int(y * H)),
            min(W, int((x + w) * W)),
            min(H, int((y + h) * H)),
        )
        if box[2] > box[0] and box[3] > box[1]:
            img = img.crop(box)

    img = img.convert("L")
    if s.brightness != 1.0:
        img = ImageEnhance.Brightness(img).enhance(s.brightness)
    if s.contrast != 1.0:
        img = ImageEnhance.Contrast(img).enhance(s.contrast)

    target_w = s.width_dots
    new_h = max(1, int(img.height * (target_w / img.width)))
    img = img.resize((target_w, new_h), Image.LANCZOS)
    return img.convert("1", dither=Image.FLOYDSTEINBERG)


def encode_and_payload(img: Image.Image, width_dots: int,
                       top: int, bottom: int) -> bytes:
    """Width-agnostic encode + build_payload using the post-2026-06-07
    firmware byte format. The `top` and `bottom` args are accepted for
    backwards compat with the UI sliders but ignored — the new firmware
    uses a fixed 1024-byte leading silence and a fixed 96-pixel
    trailing feed. See docs/runbooks/peripage-protocol-change.md."""
    row_bytes = width_dots // 8
    width, height = img.size
    assert width == width_dots, f"width {width} != {width_dots}"
    raw = img.tobytes()
    assert len(raw) == row_bytes * height
    image_bytes = bytes(b ^ 0xFF for b in raw)

    xL, xH = row_bytes & 0xFF, (row_bytes >> 8) & 0xFF
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
    return b"".join(parts)


INDEX_HTML = """
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Peripage Web UI</title>
<style>
  body { font: 14px -apple-system, system-ui, sans-serif; max-width: 720px;
         margin: 24px auto; padding: 0 16px; color: #222; }
  h1 { font-size: 18px; margin: 0 0 16px; }
  .panel { border: 1px solid #ddd; border-radius: 8px; padding: 16px;
           margin-bottom: 16px; background: #fafafa; }
  .row { display: flex; gap: 8px; align-items: center; margin: 8px 0;
         flex-wrap: wrap; }
  button { font: inherit; padding: 6px 12px; border: 1px solid #bbb;
           background: white; border-radius: 6px; cursor: pointer; }
  button:hover { background: #f0f0f0; }
  button.primary { background: #2563eb; color: white; border-color: #2563eb; }
  button.primary:hover { background: #1d4ed8; }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  input[type=range] { width: 200px; }
  label { display: inline-block; min-width: 80px; }
  .preview { background: #eee; padding: 8px; display: inline-block;
             border-radius: 4px; }
  .preview img { display: block; image-rendering: pixelated;
                 max-width: 100%; }
  #cropWrap { position: relative; display: inline-block;
              background: #222; border-radius: 4px; padding: 0;
              user-select: none; -webkit-user-select: none; }
  #cropImg { display: block; max-width: 100%; }
  #cropCanvas { position: absolute; top: 0; left: 0; cursor: crosshair; }
  .hint { color: #888; font-size: 12px; margin-top: 6px; }
  .status { font-family: ui-monospace, monospace; font-size: 12px;
            white-space: pre-wrap; color: #555; min-height: 1em; }
  .meta { color: #666; font-size: 12px; }
</style>
</head>
<body>

<h1>Peripage Web UI</h1>

<div class="panel">
  <div class="row">
    <input type="file" id="file" accept="image/*,.heic">
    <span id="filename" class="meta"></span>
  </div>
</div>

<div class="panel">
  <div class="row">
    <button onclick="rot(-90)">⟲ Rotate CCW</button>
    <button onclick="rot(90)">⟳ Rotate CW</button>
    <button onclick="flip('h')">⇄ Flip H</button>
    <button onclick="flip('v')">⇅ Flip V</button>
    <button onclick="reset()">Reset</button>
  </div>
  <div class="row">
    <label for="brightness">Brightness</label>
    <input type="range" id="brightness" min="0.3" max="2.0" step="0.05" value="1.0">
    <span id="brightnessVal" class="meta">1.00</span>
  </div>
  <div class="row">
    <label for="contrast">Contrast</label>
    <input type="range" id="contrast" min="0.5" max="2.5" step="0.05" value="1.2">
    <span id="contrastVal" class="meta">1.20</span>
  </div>
  <div class="row">
    <label for="top">Top px</label>
    <input type="number" id="top" value="40" min="0" max="500" style="width:70px">
    <label for="bottom">Bottom px</label>
    <input type="number" id="bottom" value="40" min="0" max="500" style="width:70px">
  </div>
  <div class="row">
    <label for="widthDots">Print width</label>
    <select id="widthDots">
      <option value="384">384 dots</option>
      <option value="512">512 dots</option>
      <option value="576" selected>576 dots (your printer)</option>
      <option value="672">672 dots</option>
      <option value="768">768 dots</option>
    </select>
    <span class="meta">Only change if you switch printers.</span>
  </div>
</div>

<div class="panel">
  <strong>Crop</strong>
  <div class="row">
    <button onclick="clearCrop()">Clear crop</button>
    <span class="meta" id="cropMeta">No crop</span>
  </div>
  <div id="cropWrap">
    <img id="cropImg" alt="">
    <canvas id="cropCanvas"></canvas>
  </div>
  <div class="hint">Drag on the image to draw a crop. Drag inside to move,
    drag corners/edges to resize.</div>
</div>

<div class="panel">
  <strong>Print preview</strong>
  <div class="meta" id="dims"></div>
  <div class="preview"><img id="preview" alt=""></div>
</div>

<div class="panel">
  <div class="row">
    <button class="primary" id="printBtn" onclick="doPrint()" disabled>
      Print to Peripage
    </button>
  </div>
  <div class="status" id="status"></div>
</div>

<script>
let hasImage = false;
let previewTok = 0;

function $(id) { return document.getElementById(id); }
function setStatus(s) { $('status').textContent = s; }

function refreshPreview() {
  if (!hasImage) return;
  const tok = ++previewTok;
  fetch('/dims').then(r => r.json()).then(d => {
    if (tok !== previewTok) return;
    $('dims').textContent =
      `Print size: ${d.width}px × ${d.height}px (${d.height}px tall on paper)`;
  });
  $('preview').src = '/preview.png?t=' + Date.now();
}

function refreshSource() {
  if (!hasImage) return;
  // Reload the crop source (changes when rotate/flip changes).
  // Crop is invalidated server-side when rotation/flip changes, so clear local rect too.
  crop = null;
  updateCropMeta();
  $('cropImg').onload = layoutCanvas;
  $('cropImg').src = '/source.png?t=' + Date.now();
}

async function postJSON(url, body) {
  const r = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  return r.json();
}

$('file').addEventListener('change', async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  const fd = new FormData();
  fd.append('image', f);
  setStatus('Uploading...');
  const r = await fetch('/upload', { method: 'POST', body: fd });
  const j = await r.json();
  if (j.ok) {
    hasImage = true;
    $('filename').textContent = j.filename + ' — ' + j.size;
    $('printBtn').disabled = false;
    setStatus('');
    refreshSource();
    refreshPreview();
  } else {
    setStatus('Upload failed: ' + j.error);
  }
});

async function rot(delta) {
  await postJSON('/transform', { rotate_delta: delta });
  refreshSource();
  refreshPreview();
}
async function flip(axis) {
  await postJSON('/transform', { flip: axis });
  refreshSource();
  refreshPreview();
}
async function reset() {
  await postJSON('/transform', { reset: true });
  $('brightness').value = 1.0; $('brightnessVal').textContent = '1.00';
  $('contrast').value = 1.2;   $('contrastVal').textContent = '1.20';
  $('top').value = 40; $('bottom').value = 40;
  refreshSource();
  refreshPreview();
}

async function clearCrop() {
  crop = null;
  updateCropMeta();
  drawCrop();
  await postJSON('/transform', { crop: null });
  refreshPreview();
}

// ---- Crop interaction ----
let crop = null;     // {x, y, w, h} in normalized 0..1 (oriented-image space)
let drag = null;     // {mode, startCrop, startX, startY}
const HANDLE = 10;   // px hit radius for handles

function $$() { return $('cropCanvas'); }
function ctx() { return $$().getContext('2d'); }

function updateCropMeta() {
  if (!crop) { $('cropMeta').textContent = 'No crop'; return; }
  $('cropMeta').textContent =
    `Crop: ${(crop.w*100).toFixed(0)}% × ${(crop.h*100).toFixed(0)}% ` +
    `at (${(crop.x*100).toFixed(0)}%, ${(crop.y*100).toFixed(0)}%)`;
}

function layoutCanvas() {
  const img = $('cropImg');
  const c = $$();
  c.width = img.clientWidth;
  c.height = img.clientHeight;
  c.style.width = img.clientWidth + 'px';
  c.style.height = img.clientHeight + 'px';
  drawCrop();
}
window.addEventListener('resize', layoutCanvas);

function cropPx() {
  if (!crop) return null;
  const c = $$();
  return {
    x: crop.x * c.width,
    y: crop.y * c.height,
    w: crop.w * c.width,
    h: crop.h * c.height,
  };
}

function drawCrop() {
  const c = $$(); const g = ctx();
  g.clearRect(0, 0, c.width, c.height);
  if (!crop) return;
  const r = cropPx();
  // Darken outside
  g.fillStyle = 'rgba(0,0,0,0.5)';
  g.fillRect(0, 0, c.width, r.y);
  g.fillRect(0, r.y, r.x, r.h);
  g.fillRect(r.x + r.w, r.y, c.width - r.x - r.w, r.h);
  g.fillRect(0, r.y + r.h, c.width, c.height - r.y - r.h);
  // Border
  g.strokeStyle = '#fff';
  g.lineWidth = 1;
  g.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
  // Handles (corners)
  g.fillStyle = '#fff';
  for (const [hx, hy] of [
    [r.x, r.y], [r.x + r.w, r.y],
    [r.x, r.y + r.h], [r.x + r.w, r.y + r.h],
  ]) {
    g.fillRect(hx - 4, hy - 4, 8, 8);
  }
  // Edge handles
  for (const [hx, hy] of [
    [r.x + r.w / 2, r.y], [r.x + r.w / 2, r.y + r.h],
    [r.x, r.y + r.h / 2], [r.x + r.w, r.y + r.h / 2],
  ]) {
    g.fillRect(hx - 4, hy - 4, 8, 8);
  }
}

function hitTest(mx, my) {
  if (!crop) return 'new';
  const r = cropPx();
  const near = (x, y) => Math.abs(mx - x) < HANDLE && Math.abs(my - y) < HANDLE;
  if (near(r.x, r.y)) return 'nw';
  if (near(r.x + r.w, r.y)) return 'ne';
  if (near(r.x, r.y + r.h)) return 'sw';
  if (near(r.x + r.w, r.y + r.h)) return 'se';
  if (near(r.x + r.w / 2, r.y)) return 'n';
  if (near(r.x + r.w / 2, r.y + r.h)) return 's';
  if (near(r.x, r.y + r.h / 2)) return 'w';
  if (near(r.x + r.w, r.y + r.h / 2)) return 'e';
  if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) return 'move';
  return 'new';
}

function setCursor(mode) {
  const map = {
    'new': 'crosshair', 'move': 'move',
    'n': 'ns-resize', 's': 'ns-resize',
    'e': 'ew-resize', 'w': 'ew-resize',
    'nw': 'nwse-resize', 'se': 'nwse-resize',
    'ne': 'nesw-resize', 'sw': 'nesw-resize',
  };
  $$().style.cursor = map[mode] || 'crosshair';
}

function getPos(e) {
  const rect = $$().getBoundingClientRect();
  const t = e.touches ? e.touches[0] : e;
  return { x: t.clientX - rect.left, y: t.clientY - rect.top };
}

function onDown(e) {
  if (!hasImage) return;
  e.preventDefault();
  const p = getPos(e);
  const mode = hitTest(p.x, p.y);
  if (mode === 'new') {
    crop = { x: p.x / $$().width, y: p.y / $$().height, w: 0, h: 0 };
    drag = { mode: 'se', startCrop: {...crop}, startX: p.x, startY: p.y };
  } else {
    drag = { mode, startCrop: {...crop}, startX: p.x, startY: p.y };
  }
  drawCrop();
}

function onMove(e) {
  const p = getPos(e);
  if (!drag) { setCursor(hasImage ? hitTest(p.x, p.y) : 'crosshair'); return; }
  const c = $$();
  const dx = (p.x - drag.startX) / c.width;
  const dy = (p.y - drag.startY) / c.height;
  let { x, y, w, h } = drag.startCrop;
  const m = drag.mode;
  if (m === 'move') { x += dx; y += dy; }
  if (m.includes('n')) { y += dy; h -= dy; }
  if (m.includes('s')) { h += dy; }
  if (m.includes('w')) { x += dx; w -= dx; }
  if (m.includes('e')) { w += dx; }
  // Clamp and normalize negative sizes
  if (w < 0) { x += w; w = -w; }
  if (h < 0) { y += h; h = -h; }
  x = Math.max(0, Math.min(1 - w, x));
  y = Math.max(0, Math.min(1 - h, y));
  w = Math.max(0, Math.min(1 - x, w));
  h = Math.max(0, Math.min(1 - y, h));
  crop = { x, y, w, h };
  updateCropMeta();
  drawCrop();
}

async function onUp() {
  if (!drag) return;
  drag = null;
  if (crop && (crop.w < 0.02 || crop.h < 0.02)) {
    crop = null;
    updateCropMeta();
    drawCrop();
    await postJSON('/transform', { crop: null });
  } else if (crop) {
    await postJSON('/transform', { crop: [crop.x, crop.y, crop.w, crop.h] });
  }
  refreshPreview();
}

const canvas = $$();
canvas.addEventListener('mousedown', onDown);
window.addEventListener('mousemove', onMove);
window.addEventListener('mouseup', onUp);
canvas.addEventListener('touchstart', onDown, { passive: false });
window.addEventListener('touchmove', onMove, { passive: false });
window.addEventListener('touchend', onUp);

let debounceTimer = null;
function debounced(fn) {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(fn, 150);
}

['brightness', 'contrast'].forEach(id => {
  $(id).addEventListener('input', () => {
    $(id + 'Val').textContent = parseFloat($(id).value).toFixed(2);
    debounced(async () => {
      await postJSON('/transform', {
        brightness: parseFloat($('brightness').value),
        contrast: parseFloat($('contrast').value),
      });
      refreshPreview();
    });
  });
});

['top', 'bottom'].forEach(id => {
  $(id).addEventListener('change', async () => {
    await postJSON('/transform', {
      top: parseInt($('top').value) || 0,
      bottom: parseInt($('bottom').value) || 0,
    });
    refreshPreview();
  });
});

$('widthDots').addEventListener('change', async () => {
  await postJSON('/transform', {
    width_dots: parseInt($('widthDots').value),
  });
  refreshPreview();
});

async function doPrint() {
  $('printBtn').disabled = true;
  setStatus('Connecting to printer...');
  try {
    const r = await fetch('/print', { method: 'POST' });
    const j = await r.json();
    setStatus(j.log || (j.ok ? 'Done.' : 'Failed: ' + j.error));
  } catch (e) {
    setStatus('Error: ' + e);
  } finally {
    $('printBtn').disabled = !hasImage;
  }
}

</script>
</body>
</html>
"""


@app.get("/")
def index():
    return render_template_string(INDEX_HTML)


@app.post("/upload")
def upload():
    f = request.files.get("image")
    if not f:
        return jsonify(ok=False, error="no file"), 400
    try:
        img = Image.open(f.stream)
        img.load()
    except Exception as e:
        return jsonify(ok=False, error=f"could not open image: {e}"), 400
    # Auto-orient: rotate landscape → portrait on upload so it fills the
    # paper height the way print_photo.py does by default. User can override
    # with the Rotate buttons.
    oriented = ImageOps.exif_transpose(img)
    # 270° CW == 90° CCW, matching print_photo.py's img.rotate(90, expand=True).
    auto_rot = 270 if oriented.width > oriented.height else 0

    with state.lock:
        state.original = img
        state.filename = f.filename or "upload"
        state.rotation = auto_rot
        state.flip_h = False
        state.flip_v = False
        state.crop = None
    return jsonify(
        ok=True,
        filename=state.filename,
        size=f"{img.width}×{img.height}",
    )


@app.post("/transform")
def transform():
    data = request.get_json(force=True) or {}
    with state.lock:
        if data.get("reset"):
            state.rotation = 0
            state.flip_h = False
            state.flip_v = False
            state.brightness = 1.0
            state.contrast = 1.2
            state.top = 40
            state.bottom = 120
        if "rotate_delta" in data:
            state.rotation = (state.rotation + int(data["rotate_delta"])) % 360
            state.crop = None    # crop is in oriented-space; rotation invalidates it
        if data.get("flip") == "h":
            state.flip_h = not state.flip_h
            state.crop = None
        if data.get("flip") == "v":
            state.flip_v = not state.flip_v
            state.crop = None
        if "crop" in data:
            c = data["crop"]
            if c is None:
                state.crop = None
            else:
                x = max(0.0, min(1.0, float(c[0])))
                y = max(0.0, min(1.0, float(c[1])))
                w = max(0.0, min(1.0 - x, float(c[2])))
                h = max(0.0, min(1.0 - y, float(c[3])))
                state.crop = (x, y, w, h) if w > 0 and h > 0 else None
        if "brightness" in data:
            state.brightness = float(data["brightness"])
        if "contrast" in data:
            state.contrast = float(data["contrast"])
        if "top" in data:
            state.top = max(0, int(data["top"]))
        if "bottom" in data:
            state.bottom = max(0, int(data["bottom"]))
        if "width_dots" in data:
            wd = int(data["width_dots"])
            # Must be a multiple of 8 (we send whole bytes per row).
            wd = (wd // 8) * 8
            state.width_dots = max(8, min(1024, wd))
    return jsonify(ok=True)


@app.get("/dims")
def dims():
    with state.lock:
        if state.original is None:
            return jsonify(width=0, height=0)
        img = render_for_print(state)
    return jsonify(width=img.width, height=img.height)


@app.get("/preview.png")
def preview():
    with state.lock:
        if state.original is None:
            return ("", 404)
        img = render_for_print(state)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return send_file(buf, mimetype="image/png")


@app.get("/source.png")
def source_png():
    """Oriented (rotated + flipped) source for the crop editor. Downscaled
    so the browser canvas isn't drawing a 4032×3024 image."""
    with state.lock:
        if state.original is None:
            return ("", 404)
        img = render_oriented(state).convert("RGB")
    MAX = 800
    if max(img.size) > MAX:
        scale = MAX / max(img.size)
        img = img.resize(
            (int(img.width * scale), int(img.height * scale)),
            Image.LANCZOS,
        )
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    buf.seek(0)
    return send_file(buf, mimetype="image/jpeg")


async def _do_print(img: Image.Image, top: int, bottom: int,
                    width_dots: int) -> str:
    log_lines: list[str] = []

    def log(s: str) -> None:
        log_lines.append(s)
        print(s)

    payload = encode_and_payload(img, width_dots, top, bottom)
    log(f"Width: {width_dots} dots ({width_dots // 8} bytes/row)")
    log(f"Payload: {len(payload):,} bytes ({img.height} rows, "
        f"top {top}px, bottom {bottom}px)")

    address = await find_printer()
    if not address:
        raise RuntimeError("No Peripage found. Printer on? Not paired with phone?")

    log(f"Connecting to {address}...")
    async with BleakClient(address) as client:
        log(f"Connected. MTU: {client.mtu_size}")
        await send_payload(client, payload)
        log("Waiting 3s for buffer drain...")
        await asyncio.sleep(3.0)
    log("Done.")
    return "\n".join(log_lines)


@app.post("/print")
def do_print():
    with state.lock:
        if state.original is None:
            return jsonify(ok=False, error="no image loaded")
        crop_desc = (
            f"x={state.crop[0]:.2f} y={state.crop[1]:.2f} "
            f"w={state.crop[2]:.2f} h={state.crop[3]:.2f}"
            if state.crop else "none"
        )
        img = render_for_print(state)
        top, bottom = state.top, state.bottom
        wd = state.width_dots
    try:
        log = asyncio.run(_do_print(img, top, bottom, wd))
        log = f"Crop: {crop_desc}\n" + log
        return jsonify(ok=True, log=log)
    except Exception as e:
        return jsonify(ok=False, error=str(e))


if __name__ == "__main__":
    print("Open http://localhost:8080")
    app.run(host="127.0.0.1", port=8080, debug=False, threaded=False)
