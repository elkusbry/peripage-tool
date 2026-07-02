# Runbook: Peripage protocol changed under us

> **When to use this:** Both `print_photo.py` and the iOS app stop printing,
> but the printer hardware is fine and the official Peripage app still
> prints. This is the exact failure mode we hit on **2026-06-07** —
> the official app silently pushed firmware that swapped the
> reset/feed/end bytes around the raster command. Use this runbook to
> capture the new bytes, decode the delta, and update the code.

---

## 0. Symptom checklist

If **all** of these are true, you're in the right runbook:

- [ ] `print_photo.py` runs cleanly, BLE writes complete, no Python errors
- [ ] iOS app log shows full chunk transmission (`sent N/N (100%)`) and a clean disconnect
- [ ] Printer reports healthy status notifications during the job (`FF03 → 01 02`/`01 01` notifications, battery showing reasonable level)
- [ ] **No paper comes out** even though every byte left the host
- [ ] The **official Peripage iOS app** prints the same content successfully
- [ ] Self-test print (hold power + paper-feed ~6 sec) prints — confirms the print head fires fine

If self-test produces blank paper or the official app also fails, **stop**
— this runbook is for protocol changes, not hardware faults. Try a factory
reset, fresh paper roll, or USB power before continuing.

---

## 1. Capture the official app's byte stream

You need a PacketLogger trace of the iPhone's BLE traffic while the official
app prints a small test image.

### 1.1 One-time Mac setup

1. Download Apple's **Additional Tools for Xcode** from
   <https://developer.apple.com/download/all> (free Apple ID).
2. Mount the `.dmg` and drag `PacketLogger.app` to `/Applications`.

### 1.2 One-time iPhone setup

1. On Mac, install the **Bluetooth Sniffing Profile** from
   <https://developer.apple.com/bug-reporting/profiles-and-logs/?platform=ios>
   → "Bluetooth" → "Bluetooth for iOS". This installs a configuration
   profile via Safari.
2. On iPhone, accept the prompt and complete the install in
   **Settings → General → VPN & Device Management**. Reboot the iPhone.

### 1.3 Capture

1. Plug iPhone into Mac via USB. Trust the computer if prompted.
2. Open `PacketLogger.app` on Mac → **File → New iOS Trace…** → pick the
   iPhone in the device list. The trace starts running.
3. On iPhone, open the **official Peripage app** and print a simple test
   image (a 50×50 black square works well — fewer bytes to wade through).
4. Wait until the print finishes (or the app errors out), then on Mac
   click **Pause** in PacketLogger.
5. **File → Save As…** → save as `peripage_capture.pklg` somewhere
   accessible.

> ⚠️ The capture includes everything the iPhone's BT controller did during
> the trace, not just the Peripage. Keep the window short and avoid
> opening other BT apps so the log is small and easy to read.

---

## 2. Decode the capture

```bash
cd ~/Repo/peripage-tool
source venv/bin/activate
python fixtures/parse_pklg.py /path/to/peripage_capture.pklg
```

The script prints:

- **Annotations** (iPhone model, iOS version, BT controller firmware)
- **Handle → UUID map** (which BLE handle corresponds to which characteristic UUID)
- **Writes per handle** (chunks + total bytes the iPhone wrote to each handle, plus the first 32 bytes of each)
- **Notifications per handle** (status the printer sent back)

The largest write-handle is dumped to a `.bin` file next to the input.
Open it with `xxd` to inspect:

```bash
xxd /path/to/peripage_capture.bin | head -50
```

### 2.1 What to look for

The Peripage's BLE protocol always has this top-level shape:

```
<wrapper-start>
<leading silence or feed>
<GS v 0 raster header>     ← 0x1D 0x76 0x30 0x00 xL xH yL yH
<raster pixel bytes>       ← rowBytes × height
<trailing feed>
<wrapper-end>
```

The raster body almost never changes — only the wrapper does. Diff the
first ~32 bytes and the last ~16 bytes of the capture against what the
current `build_payload` produces:

```bash
python3 -c "
import sys; sys.path.insert(0, '.')
from print_photo import build_payload, ROW_BYTES
fake = b'\x00' * (ROW_BYTES * 455)
out = build_payload(fake, 455)
captured = open('/path/to/peripage_capture.bin', 'rb').read()
print('Ours    header:', out[:16].hex())
print('Captured header:', captured[:16].hex())
print('Ours    tail:  ', out[-16:].hex())
print('Captured tail: ', captured[-16:].hex())
print('Length match:  ', len(out) == len(captured))
"
```

If headers differ, the **init/reset command** changed. If tails differ,
the **end command** and/or **trailing feed** changed. If lengths differ
but headers + tails match, the **leading silence** length or
**raster-block split rule** changed.

---

## 3. Update the protocol

The change must land in **three places**, kept in lockstep:

### 3.1 `print_photo.py` — source of truth

Update the constants block (near the top of the file, just above
`find_printer`). The constants we hit on 2026-06-07:

```python
CMD_START_A = bytes.fromhex("10ff100001")  # session init
CMD_START_B = bytes.fromhex("10fffe01")    # ready / clear buffer
CMD_END     = bytes.fromhex("10fffe45")    # commit and print
LEADING_SILENCE_BYTES = 1024
TRAILING_FEED_PX = 96
```

Then update `build_payload()` to assemble the new wrapper. The body
(`GS v 0` raster command + pixel bytes) is unchanged.

### 3.2 `webui.py` — keep imports current

`webui.py` has its own inlined copy of the wrapper assembly (see
`encode_and_payload`). It imports the protocol constants from
`print_photo.py` — so if you update the constants in `print_photo.py`,
make sure the `from print_photo import ...` line in `webui.py` pulls
in any newly-added names, and that `encode_and_payload`'s `parts = [...]`
list matches the structure in `build_payload`.

> ⚠️ This bit me on 2026-06-07: I updated `print_photo.build_payload`
> but didn't realize the web UI had its own copy of the wrapper bytes.
> The web UI silently kept printing the old format. Always grep for
> `1011fffe01` or whatever the old reset bytes were, across the whole
> repo, to find stragglers.
>
> ```bash
> grep -rn "1011fffe01" --include="*.py" --include="*.swift"
> ```

### 3.3 `ios/Peripage/Protocol/PeripageProtocol.swift` — Swift mirror

Update the constants:

```swift
public static let cmdStartA = Data([0x10, 0xff, 0x10, 0x00, 0x01])
public static let cmdStartB = Data([0x10, 0xff, 0xfe, 0x01])
public static let cmdEnd    = Data([0x10, 0xff, 0xfe, 0x45])
public static let leadingSilenceBytes: Int = 1024
public static let trailingFeedPx: UInt8 = 96
```

Then mirror the new `buildPayload()` structure exactly. **Critical:** every
byte must match Python — the parity tests will catch you if they don't.

### 3.4 Transport pacing (separate from payload bytes)

The inter-chunk pacing constants (`INTER_CHUNK_S` / `MAX_BACKLOG_S` in
`print_photo.py`, `interChunkDelay` / `maxPacingBacklog` in
`PeripageProtocol.swift`) also live in lockstep across the two send loops,
but they are **transport tuning, not payload bytes**. Changing them does NOT
change the assembled payload and does NOT require regenerating the parity
fixtures (the fixtures cover `encodeImageToBytes` / `buildPayload` output
only). Both loops are deadline-paced: chunk *n* goes no earlier than
`anchor + n × interval`, so overshoot self-corrects rather than accumulating
into a printer-side underrun gap. If prints show shifted/torn rows instead of
blank lines, that's receive-buffer overrun — raise the interval back toward
15ms.

---

## 4. Regenerate fixtures and verify

```bash
# 1. Regenerate the Python-produced reference files
source venv/bin/activate
python fixtures/generate_fixtures.py

# 2. Run the Swift parity tests — they should still pass since they
#    load the regenerated fixtures and assert Swift produces the same.
cd ios && xcodegen generate && cd ..
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests \
  2>&1 | grep -E "Test run|TEST"
```

Expected: `Test run with 13 tests in 3 suites passed`.

If a test fails, the Swift `buildPayload` does **not** match what Python
produces. Print both sides' bytes and diff until they match.

---

## 5. End-to-end verify against the real printer

The cheapest sanity check, in order:

1. **Python CLI first** — fastest feedback loop, no Xcode dance:
   ```bash
   source venv/bin/activate
   python print_photo.py path/to/test.jpg
   ```
   If it prints, the protocol fix is correct. Proceed to step 2.
2. **iOS** — build and run on your phone, print one photo.
3. **macOS** — build and run, print one photo (macOS uses the same code path).

If Python prints but iOS doesn't, the protocol is fine and the issue is
BLE transport (queue overflow, write-type, etc.) — see the BLE flow control
notes in `ios/Peripage/Printer/PrinterClient.swift`.

---

## 6. Capture-mode fallback (if PacketLogger isn't available)

The iOS app has a built-in **BLE Capture** mode (`HomeView` → small
"BLE Capture" link). It advertises this iPhone as a fake Peripage so the
official app connects to us and dumps its bytes. Less reliable than
PacketLogger (the official app may store the real device's identifier and
refuse to connect to anything else), but useful as a last resort.

Trigger: power the real printer off, forget any bonded "PeriPage" devices
in iOS Bluetooth settings, then open the capture screen and tap Start.
If the official app stubbornly refuses to connect to us, fall back to
PacketLogger.

---

## 7. Things that look like protocol changes but aren't

Before going down this whole runbook, rule out the cheaper causes:

| Symptom | Likely cause | Fix |
|---|---|---|
| Bytes leave host, no notifications come back | Thermal paper loaded backwards | Scratch-test the paper; coated side faces the print head |
| Connection succeeds, writes fail silently mid-job | CoreBluetooth `.withoutResponse` queue overflow | Use `canSendWriteWithoutResponse` flow control (already in `PrinterClient.swift`) |
| Job marks `.done`, no paper, but Python also fails | Printer in fault state | Power cycle 10+ sec, then factory reset (power + paper-feed held 10 sec on power-on) |
| Battery reports 100% but no print | Reading is stale | Plug into known-good USB-C charger for 30 min and retry |

If any of these fit, fix them first. Only run the capture-and-decode
flow when the official app prints and yours doesn't — that's the unique
fingerprint of a real protocol change.

---

## Appendix: the 2026-06-07 firmware delta

For reference, here's the exact change we hit, in case the firmware
flips back or partly reverts:

| Field | Pre-change | Post-change |
|---|---|---|
| Init at start | `10 11 FF FE 01` (5 B) | `10 FF 10 00 01` + `10 FF FE 01` (9 B) |
| Leading feed format | `1B 4A n` (ESC J n) | 1024 × `0x00` raw bytes |
| Raster header | `1D 76 30 00 xL xH yL yH` | same |
| Raster blocks | split at 256 rows | single block, no split |
| Trailing feed | `1B 4A n` (configurable) | `1B 4A 60` (fixed 96 px) |
| End | `10 11 FF FE 01` | `10 FF FE 45` |

Captured against a `PeriPage+064E_BLE` running firmware version unknown
(no firmware report endpoint was queried during the capture; if you
want to know which version this is, capture again with
`peripheral.read_gatt_char(0x2A28)` in bleak — that's the Software
Revision String in the standard Device Information service `180A`).
