# Peripage Tool — current state

> Last touched: 2026-06-07. Things are **working** — prints come out
> of the printer from all three clients. This file is the 90-second
> orientation for whoever picks this up next.

## What you can do right now

| Client | Where | How |
|---|---|---|
| **CLI** | `print_photo.py` | `source venv/bin/activate && python print_photo.py path/to/photo.jpg` |
| **Web UI** | `webui.py` | `python webui.py` → open <http://127.0.0.1:5000> in a browser |
| **Finder Quick Action** | `scripts/print_to_peripage.sh` | Right-click image in Finder → Quick Actions → Print to Peripage (the wrapper is installed by Automator; the shell script lives in this repo) |
| **iOS app** | `ios/` (Xcode) | Open `ios/Peripage.xcodeproj`, build to your iPhone. Bundle ID is `com.elkus.peripage`. Team ID lives in `ios/developer.xcconfig` (gitignored). |
| **iOS Share Sheet** | `PeripageShare` target | Built alongside the main app. After installing, "Print to Peripage" appears in Photos.app's share sheet (sometimes you have to enable it once via the "..." → Edit Actions). |
| **macOS app** | same Xcode project | Same target, "My Mac" destination. |

## Where the protocol lives

The byte-level Peripage protocol is duplicated across **three** files —
they must stay in lockstep. If you change one, change all three:

1. `print_photo.py` — Python, used by CLI + the Automator wrapper
2. `webui.py` — Python, imports the constants from `print_photo.py` but
   has its own copy of the assembly logic
3. `ios/Peripage/Protocol/PeripageProtocol.swift` — Swift, used by the
   iOS app, macOS app, and the Share Extension

Parity is enforced by `ios/PeripageTests/ProtocolParityTests`, which
reads fixtures generated from `print_photo.py` and asserts the Swift
output matches byte-for-byte.

## If prints stop working

Open `docs/runbooks/peripage-protocol-change.md`. It walks through:

1. Ruling out hardware / paper / BLE-state issues
2. Capturing the official app's bytes via Apple PacketLogger (preferred)
   or the in-app BLE Capture mode (long-press status pill → Debug Log →
   antenna icon)
3. Decoding the capture with `fixtures/parse_pklg.py`
4. Updating all three protocol sites in lockstep
5. Regenerating fixtures + verifying tests still pass

The runbook also has a triage table for the cheaper failure modes
(paper loaded backwards, dead battery, BLE queue overflow, etc.) so
you don't run the whole capture-and-decode flow for a hardware fix.

## Repo layout

```
peripage-tool/
├── print_photo.py             CLI tool — source of protocol truth
├── webui.py                   Flask-based local web UI
├── scan.py / diagnose.py      BLE scan + per-char inspection helpers
├── scripts/                   Automator Quick Action wrapper
├── fixtures/
│   ├── generate_fixtures.py   Builds the .bin reference files for Swift tests
│   ├── parse_pklg.py          Decodes Apple PacketLogger .pklg captures
│   ├── peripage_capture.pklg  The 2026-06-07 capture (forensic record)
│   ├── peripage_capture.bin   Decoded bytes from that capture
│   └── make_app_icon.py       Generates the dithered app icon from PIL
├── docs/
│   ├── runbooks/peripage-protocol-change.md   The SOP if prints break
│   └── superpowers/specs+plans/               Original design + impl plan
├── ios/
│   ├── Project.yml            xcodegen config (one source of truth)
│   ├── developer.xcconfig     YOUR Apple Developer team ID (gitignored)
│   ├── Peripage/              Main app (iOS + macOS targets)
│   │   ├── Protocol/          ← shared with PeripageShare via xcodegen
│   │   ├── Imaging/           ← shared with PeripageShare
│   │   ├── Printer/           ← shared with PeripageShare
│   │   ├── Queue/             ← shared with PeripageShare
│   │   ├── App/               SwiftUI views (Home, Preview, Queue, Debug, Capture)
│   │   ├── Capture/           BLE peripheral-mode capture client
│   │   └── Resources/         Info.plist, entitlements, app icon
│   ├── PeripageShare/         iOS Share Extension target
│   ├── PeripageTests/         Swift Testing suite + fixtures
│   └── CHANGELOG.md           Release notes
└── STATUS.md                  ← you are here
```

## Regenerate the Xcode project

`ios/Peripage.xcodeproj/` is `.gitignore`d; `xcodegen` generates it
from `ios/Project.yml`. If anything seems off after a `git pull` or
branch switch:

```bash
cd ios && xcodegen generate && cd ..
```

## Outstanding ideas / nice-to-haves (not pressing)

- Share Extension large-photo handling: very tall photos may exceed the
  extension's 120 MB runtime budget. Plan was an App-Group hand-off to
  the host app for processing. Not blocking — most photos fit fine.
- The `working-2026-06-05` and `capture-mode` branches were merged into
  `main` and deleted. Git log preserves the history if you need to
  spelunk the 2026-06-07 debugging arc.
