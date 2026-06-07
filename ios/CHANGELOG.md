# Peripage App Changelog

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
