# peripage-tool

Print photos to a **Peripage A6** thermal printer (the 576-dot, BLE-only
firmware variant) from anywhere: a Python CLI, a local web UI, a Finder
Quick Action, an iOS app, the iOS Share Sheet, and a native Mac app.

The official Peripage app works fine — this exists because I wanted:

- a **CLI** so I can shell-script prints,
- a **Finder right-click** so printing a photo is one click,
- and an **iOS Share Sheet entry** so "Photos → Share → Print to Peripage"
  is a real option without round-tripping through the vendor app.

All clients speak the same byte-level protocol and produce identical
output. The protocol is reverse-engineered from BLE captures of the
official app; see [`docs/runbooks/peripage-protocol-change.md`](docs/runbooks/peripage-protocol-change.md)
for the methodology if the firmware ever shifts again.

## What's in the box

| Client | Where | Status |
|---|---|---|
| Python CLI | [`print_photo.py`](print_photo.py) | Working |
| Local web UI (Flask) | [`webui.py`](webui.py) | Working |
| Finder Quick Action wrapper | [`scripts/print_to_peripage.sh`](scripts/print_to_peripage.sh) | Working |
| iOS app | [`ios/`](ios/) | Working |
| iOS Share Extension | `ios/PeripageShare/` | Working |
| macOS app | same Xcode project, "My Mac" destination | Working |
| BLE scan / diagnose helpers | [`scan.py`](scan.py), [`diagnose.py`](diagnose.py) | Working |

## Quick start (Python CLI)

Requires Python 3.10+ and a Mac or Linux box with Bluetooth.

```bash
git clone https://github.com/YOUR-USER/peripage-tool.git
cd peripage-tool
python3 -m venv venv
source venv/bin/activate
pip install pillow pillow-heif bleak flask
python print_photo.py path/to/photo.jpg
```

Turn the printer on, hold it close, and the script will scan, connect,
and print. Use `--no-print` to render the dithered preview to
`/tmp/peripage_preview.png` without touching the printer.

### Web UI

```bash
python webui.py
# open http://127.0.0.1:5000
```

Drop a photo in, tune brightness/contrast/rotation, hit Print. Same
protocol as the CLI; useful when you want to eyeball the dither before
committing paper.

### Finder Quick Action

`scripts/print_to_peripage.sh` is the shell wrapper. Wire it into a
Quick Action via Automator → "Run Shell Script" → "Pass input as
arguments", and "Print to Peripage" appears under right-click → Quick
Actions on any image in Finder.

## iOS / macOS app

```bash
brew install xcodegen
cd ios
cp developer.xcconfig.template developer.xcconfig
# edit developer.xcconfig and put your Apple Developer team ID in
xcodegen generate
open Peripage.xcodeproj
```

The bundle IDs are `com.elkus.peripage` and `com.elkus.peripage.share`
— you'll want to change these to your own reverse-DNS in
[`ios/Project.yml`](ios/Project.yml) before signing for distribution.
For personal sideloading they're fine as-is.

Build to your iPhone, install. "Print to Peripage" then shows up in
Photos.app's share sheet (you may need to enable it once under "…" →
Edit Actions on first run).

## How the protocol works (~)

- BLE GATT, write characteristic `0000ff02-...`.
- Reset / init: `10 11 FF FE 01`, then `10 FF FE 01`, then 1024 zeros
  of silence to let the firmware settle.
- Image: one big `GS v 0` raster block, 576 dots (72 bytes) wide,
  1-bit-per-pixel MSB-first, white pixel → bit 0 (invert from PIL).
- Top and bottom feeds: `1B 4A <n>`.
- End-of-job: `10 FF FE 45`.

Floyd–Steinberg dither before packing. Auto-rotation rotates landscape
photos 90° CW so the long axis runs down the receipt strip; portrait /
square photos print at 0°.

The **same byte-building logic is duplicated in three places** —
`print_photo.py`, `webui.py`, and
`ios/Peripage/Protocol/PeripageProtocol.swift` — and they must stay in
lockstep. Swift parity is enforced by
`ios/PeripageTests/ProtocolParityTests` against fixtures generated from
the Python.

## Repo layout

```
peripage-tool/
├── print_photo.py             CLI tool — source of protocol truth
├── webui.py                   Flask-based local web UI
├── scan.py / diagnose.py      BLE scan + per-characteristic inspection
├── scripts/                   Automator Quick Action wrapper
├── fixtures/
│   ├── generate_fixtures.py   Builds .bin reference files for Swift tests
│   ├── parse_pklg.py          Decodes Apple PacketLogger .pklg captures
│   └── ...                    Sample capture + decoded bytes
├── docs/
│   ├── runbooks/              The SOP if prints stop working
│   └── superpowers/           Specs + plans from AI-paired build sessions
├── ios/
│   ├── Project.yml            xcodegen config (one source of truth)
│   ├── Peripage/              Main app (iOS + macOS targets)
│   ├── PeripageShare/         iOS Share Extension target
│   ├── PeripageTests/         Swift Testing suite + fixtures
│   └── CHANGELOG.md           Release notes
├── STATUS.md                  Maintainer's-eye orientation doc
└── README.md                  You are here
```

## Hacking on it

If prints stop working — usually after a Peripage firmware bump —
follow [`docs/runbooks/peripage-protocol-change.md`](docs/runbooks/peripage-protocol-change.md).
It walks through capturing the official app's bytes (Apple
PacketLogger or the in-app BLE Capture mode), decoding them, updating
all three protocol sites in lockstep, and regenerating Swift test
fixtures.

[`STATUS.md`](STATUS.md) is the day-to-day maintainer orientation —
what works, where things live, what's outstanding.

The [`docs/superpowers/`](docs/superpowers/) folder holds the original
design specs and step-by-step implementation plans. These were written
in pair with Claude during the build sessions and kept around as
documentation-of-record.

## Hardware

Tested against a **Peripage A6** that reports as `PeriPage_*` over BLE
and prints at 576 dots wide on 57 mm paper. Older A6 units are 384
dots wide and won't work without changing `PRINT_WIDTH_PX`. The A6+,
A9, A9s, and similar variants have not been tested.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- The Peripage reverse-engineering community for early protocol notes
  (`GS v 0`, the 0x10 0xFF wrapper bytes).
- [`bleak`](https://github.com/hbldh/bleak) for cross-platform BLE that
  Just Works on macOS.
- Most of this codebase was built in pair with Claude. Specs and plans
  in [`docs/superpowers/`](docs/superpowers/) are the unedited record
  of those sessions if you're curious what AI-paired development
  actually looks like at the prompt level.
