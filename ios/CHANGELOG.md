# Peripage App Changelog

## 0.3.0 — 2026-06-07 (afternoon)

- **Protocol updated to the post-firmware-bump byte format.** The official
  Peripage app pushed firmware that swapped the reset/feed/end bytes
  around the raster command. New wrapper (in lockstep across
  `print_photo.py`, `webui.py`, and `PeripageProtocol.swift`):
  `10 FF 10 00 01` + `10 FF FE 01` + 1024 silence + one big GS v 0 block
  + `1B 4A 60` + `10 FF FE 45`. See
  `docs/runbooks/peripage-protocol-change.md` for how to diagnose and
  fix this if it happens again.
- **BLE diagnostics promoted.** CoreBluetooth `.withoutResponse` flow
  control via `canSendWriteWithoutResponse` + `peripheralIsReady`. Auto-
  subscribe to every notify characteristic and wait for ACK before
  sending the first byte. Live-on-Home 3-line log tail, plus a hidden
  BLE Capture mode (long-press status pill → Debug Log → antenna icon)
  that makes this iPhone advertise as a fake Peripage so the official
  app's bytes can be recorded for diffing.
- **PacketLogger decoder** at `fixtures/parse_pklg.py` for offline
  analysis of `.pklg` captures.
- **Auto-rotation revised:** landscape sources rotate 90° clockwise so
  the long axis runs down the strip; portraits stay at 0° and print in
  their natural orientation. (Set per-photo overrides via the Rotation
  picker.)
- **UI cleanup:** Brightness and Contrast are 3-tier button groups
  (Dim/Normal/Bright, Soft/Normal/Bold), top + bottom margins fixed at
  40 px and removed from the UI, Print button promoted to dominant
  action, Add to Queue demoted. BLE Capture hidden behind the debug log.

## 0.2.0 — 2026-06-07

- iOS Share Extension: "Print to Peripage" in any app's share sheet for `public.image` items
- Reuses the host app's `ImageProcessor` + `PeripageProtocol` so print output is byte-identical
- Single-photo flow inside the share sheet: live preview, all four sliders, rotation, Print
- Failure paths surface a "Try again" / "Cancel" choice instead of dumping a stack trace
- Known limitation: very tall photos may exceed the extension's runtime budget; follow-up tracks an App Group hand-off to the host app

## 0.1.0 — 2026-06-05

- Initial release of Peripage iOS + macOS app
- Single SwiftUI multiplatform target (iOS 17 / macOS 14)
- Live-preview dithered output with brightness, contrast, top margin, bottom margin sliders
- Auto-rotation: portraits rotate 90° clockwise so long axis fits the 576px print width; landscape stays put. Manual override available (0° / 90° / 180° / 270°).
- Serial print queue with pause / resume / cancel / clear-completed
- Auto-pause after two consecutive connect failures
- Hidden debug log (long-press the status pill) with share sheet
- Byte-for-byte protocol parity with `print_photo.py`, asserted via Python-generated fixtures
