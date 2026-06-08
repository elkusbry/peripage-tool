# How this was built

A short writeup of the process behind `peripage-tool` — what model and
harness drove it, how the BLE protocol was reverse-engineered, and where
the trial-and-error went. Pieced together from the repo's git history,
runbooks, and design docs.

## Model and harness

- **Claude Opus 4.7** in **Claude Code**. Every commit is co-authored by
  that model.
- Used the **superpowers** skill pack (see `docs/superpowers/specs/` and
  the TDD-shaped commit pattern: `test: failing X` followed by
  `implement X`, dozens of pairs).
- Overall workflow: design spec → implementation plan → execute the plan,
  with TDD enforced inside each step.

## Timeline

- **~3 calendar days, June 5 → June 8, 2026. 93 commits.**
- The **Python CLI and BLE protocol were solved before `git init`** —
  the very first commit already had `print_photo.py` and `webui.py`
  printing successfully. The 93 commits cover the iOS app, macOS app,
  Share Extension, and supporting tests/docs.
- A mid-project crisis on June 7: the official Peripage app silently
  shipped a firmware update that changed the reset/feed/end bytes around
  the raster command. Both Python and iOS stopped printing even though
  the printer hardware was fine. That whole debugging arc is what
  produced the protocol-change runbook.

## How the packet sniffing was guided

The methodology is captured in
[`docs/runbooks/peripage-protocol-change.md`](runbooks/peripage-protocol-change.md).
Claude can't run any of the physical capture steps — those are on the
human:

1. Install Apple's **PacketLogger** (ships with Additional Tools for
   Xcode) on the Mac.
2. Install Apple's **Bluetooth Sniffing Profile** on the iPhone and
   reboot.
3. Plug the iPhone into the Mac via USB, start a trace in PacketLogger,
   print a small test image from the **official** Peripage app, save
   the `.pklg`.
4. Claude then wrote [`fixtures/parse_pklg.py`](../fixtures/parse_pklg.py)
   to decode the handle/UUID map, dump the largest write to a `.bin`,
   and a one-liner that diffs the captured wrapper bytes against what
   `build_payload()` produces locally.

The protocol always has the same top-level shape:

```
<wrapper-start>
<leading silence or feed>
<GS v 0 raster header>      ← 0x1D 0x76 0x30 0x00 xL xH yL yH
<raster pixel bytes>        ← rowBytes × height
<trailing feed>
<wrapper-end>
```

The pixel body almost never changes — only the wrapper. So diffing the
first ~32 bytes and the last ~16 bytes of the capture against the
current implementation localises the change quickly.

## Trial and error worth flagging

- **The printer docs lie.** The Peripage A6 manual claims 384-dot /
  203 DPI, but the actual hardware is **576-dot / 300 DPI**. This was
  calibrated empirically against printed strips, not from documentation.
- **Auto-rotation flipped twice.** The "which axis is the long axis"
  rule got reversed and then reversed again before settling on
  "landscape sources rotate 90° clockwise, portrait/square stay at 0°".
  Noted as a hard invariant in the session-memory file so future
  sessions don't try to flip it a third time.
- **Three protocol implementations, one source of truth.** The Peripage
  byte protocol is duplicated across `print_photo.py`, `webui.py`, and
  `ios/Peripage/Protocol/PeripageProtocol.swift`. Parity is enforced by
  Swift tests that load `.bin` fixtures generated from the Python and
  assert byte-for-byte equality. This guard rail caught a real drift on
  June 7: the Python source got patched first, and `webui.py`'s inlined
  copy of the wrapper was silently still printing the old format until
  the grep across the repo turned it up.
- **In-app capture mode as a fallback.** When PacketLogger isn't
  available, the iOS app has a hidden "BLE Capture" mode where it
  advertises itself as a fake Peripage so the official app connects to
  it and dumps its bytes. It's flakier than PacketLogger (the official
  app caches the real device's identifier and sometimes refuses), but
  useful as a last resort.

## If you want to read just one file

[`docs/runbooks/peripage-protocol-change.md`](runbooks/peripage-protocol-change.md)
— it's the entire capture → decode → update → verify loop in 270 lines,
including the exact byte delta from the June 7 firmware change.
