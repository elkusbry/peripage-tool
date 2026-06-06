# Peripage iOS + macOS App — Design

**Date:** 2026-06-05
**Status:** Approved, ready for implementation plan
**Source tool:** `print_photo.py`, `scan.py`, `diagnose.py` (in this repo)

## Goal

Port the working Python Peripage A6 print tool to a single SwiftUI multiplatform app that runs on iPhone and Mac. Same protocol, same print output, plus a phone-native UX: live-preview adjustments and a serial print queue.

## v1 scope

In:

- Pick a photo from the system photo library
- Live-preview the dithered output as you adjust brightness, contrast, top margin, bottom margin, and rotation
- Print one photo, or enqueue several and have them print serially
- iOS and macOS from a single Xcode target

Out of v1 (explicitly deferred):

- Camera capture
- History of recent prints
- Adjustment presets
- App Store distribution (sideload via paid Apple Developer account)

## Distribution

Personal sideload via Bryan's paid Apple Developer account. No App Store submission planned for v1. TestFlight is available if a second tester is ever needed.

## Architecture

Approach: single SwiftUI Multiplatform App target, destinations = iPhone + Mac (Designed for iPad/Mac, **not** Mac Catalyst). Minimum deployment iOS 17 / macOS 14 so we get `PhotosPicker` and `@Observable`. No third-party dependencies — CoreBluetooth, CoreGraphics, PhotosUI, SwiftUI are sufficient.

Rationale for single target vs. shared Swift Package: the two apps do the same thing, and ~95% of the code is identical. A package split is straightforward to introduce later if either platform's UI diverges.

### Modules (folders under one target)

- **`Protocol/`** — pure, stateless port of the Python protocol code. Constants: `PRINT_WIDTH_PX = 384`, `ROW_BYTES = 48`, `CHUNK_SIZE = 96`, `ROWS_PER_BLOCK = 256`, `WRITE_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"`, `CMD_RESET = Data([0x10, 0x11, 0xff, 0xfe, 0x01])`, name prefix `"PeriPage"`. One key function: `buildPayload(rasterBytes:height:leadingFeed:trailingFeed:) -> Data` that mirrors Python's `build_payload` byte-for-byte.
- **`Imaging/`** — `ImageProcessor` takes `Data` (HEIC/JPG/PNG) plus an `Adjustments` struct and returns `(previewImage, rasterBytes)`. CoreGraphics for EXIF transpose, rotation, resize to 384 wide. Floyd–Steinberg dither + invert (white pixel → bit 0, matching Python's XOR with 0xFF).
- **`Printer/`** — `PrinterClient`, an `@Observable` actor wrapping `CBCentralManager`. Async API: `scan() async throws -> Peripheral`, `connect(_:)`, `write(_ data: Data)` (chunks at 96 bytes with 15 ms gap, exactly like the Python). Publishes `state: Disconnected / Scanning / Connected / Sending(progress)`.
- **`Queue/`** — `PrintQueue`, `@Observable`. Holds `[PrintJob]` where a job is `{ id, sourceData, adjustments, status }`. A single worker task drains the queue serially, holding the BLE connection open across jobs and reconnecting only on disconnect.
- **`App/`** — SwiftUI scenes, views, view models.

### Data flow for one print

```
PhotosPicker  → Data
              → ImageProcessor.process(data, adjustments) → (preview, rasterBytes)   [for live preview]
              → user taps "Add to queue"
              → PrintQueue.enqueue(PrintJob(sourceData, adjustments))
              → worker pops next job
                  → ImageProcessor.process(sourceData, job.adjustments) → rasterBytes  [recomputed at print time]
                  → Protocol.buildPayload(rasterBytes, height, top, bottom)
                  → PrinterClient.ensureConnected()
                  → PrinterClient.write(payload)
                  → job.status = .done; connection held open for next job
```

Jobs hold the *source image data plus the adjustments*, not the rendered raster. Re-rendering at print time is fast on phone hardware (sub-second) and keeps memory low for paused queues.

## Screens

Three screens, same on both platforms with minor chrome tweaks.

### HomeView

Root of the app. Shows:

- A large `PhotosPicker` button labeled "Choose Photo"
- A status pill near the top reflecting `PrinterClient.state` and queue depth — examples: "Idle", "Scanning…", "Connected · 2 in queue", "Sending… 43%"
- A "Queue (n)" button that opens QueueView (hidden when queue is empty)

macOS: centered in a min 540×640 window. iOS: fills the screen.

### PreviewView

Pushed (iOS) / opened in detail pane or sheet (macOS) after a photo is picked.

- **Top half**: dithered preview rendered at native 384 px width, displayed scaled-to-fit with a checkerboard background so the actual print output is visible
- **Bottom half**: four sliders
  - Brightness: 0.5–2.0, default 1.0
  - Contrast: 0.5–2.0, default 1.2
  - Top margin: 0–300 px, default 40
  - Bottom margin: 0–300 px, default 120
- **Rotation control**: a 5-position segmented picker — `Auto · 0° · 90° · 180° · 270°`. Default is `Auto`.
- **Auto rotation rule**: after EXIF transpose, if `image.width >= image.height` (landscape), rotate 0°. Otherwise (portrait), rotate 90° clockwise. Goal: the photo's long axis always fits the 384 px print width, yielding compact prints (no 4-foot receipts). This is the **opposite** of the current Python behavior, which rotates landscapes so the long axis runs down the strip.
- **Buttons**: "Add to queue" (always available); "Print now" (adds + immediately starts the queue if idle)
- Slider/rotation changes are debounced ~150 ms before re-dithering, so the preview doesn't recompute on every drag tick

### QueueView

List of jobs with thumbnails and status (`Pending` / `Sending xx%` / `Done` / `Failed(reason)`).

- iOS: swipe-to-cancel on each row
- macOS: context-menu cancel on each row
- Top of view: "Pause" / "Resume" toggle, "Clear completed" button

## Data model

```swift
struct Adjustments: Equatable, Codable {
    var brightness: Double = 1.0
    var contrast: Double = 1.2
    var topMarginPx: Int = 40
    var bottomMarginPx: Int = 120
    var rotation: Rotation = .auto    // .auto | .deg0 | .deg90 | .deg180 | .deg270
}

struct PrintJob: Identifiable {
    let id: UUID
    let sourceData: Data
    let adjustments: Adjustments
    var status: JobStatus    // .pending | .rendering | .sending(progress) | .done | .failed(reason)
}
```

`PrinterClient.State` (published via `@Observable`):

```
.disconnected
.scanning
.connected(peripheralName)
.sending(jobId, progress: Double)
.error(BLEError)
```

## Error handling

- **Bluetooth off or unauthorized** → blocking sheet on app launch with an "Open Settings" deep-link. iOS: `UIApplication.openSettingsURLString`. macOS: `x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth`. Queue refuses to start until resolved.
- **Scan timeout (8s, matching Python)** → non-blocking banner: "No Peripage found — make sure it's on and not paired to another device." Queue pauses; the next "Print now" or "Resume" retries.
- **Mid-send disconnect** → current job → `.failed(reason)` with a Retry button. Queue continues with the next job after a fresh reconnect attempt; two consecutive reconnect failures auto-pause the queue.
- **Photo decode failure** (corrupt HEIC, etc.) → inline toast on PreviewView; job never enqueued.
- **Ring-buffer debug log** — all error events plus connection lifecycle entries land in an in-memory ring buffer (last 200 entries). A hidden "Debug" sheet, accessed by long-pressing the status pill, displays it and offers a share action. Cheap to ship, invaluable when something doesn't print.

## Platform differences

`#if os(...)` branches are confined to UI chrome; the protocol/imaging/printer/queue layers are 100% shared.

**iOS-only:**

- Success haptic (`UINotificationFeedbackGenerator.success`) on job completion
- Swipe gestures in QueueView
- Sheet-style presentation for PreviewView
- `NSPhotoLibraryUsageDescription` in Info.plist

**macOS-only:**

- 540×640 minimum window
- `.toolbar` placement of action buttons instead of bottom buttons
- Context-menu cancel in QueueView
- No haptics
- Bluetooth entitlement in the sandbox (`com.apple.security.device.bluetooth`)

**Both:**

- `NSBluetoothAlwaysUsageDescription` in Info.plist

## Testing strategy

- **Protocol parity tests** — run Python `build_payload` on a fixed test image with known adjustments, freeze the byte output as a checked-in fixture, and write a Swift unit test that asserts the Swift `buildPayload` produces byte-identical output. Same for `encodeImageToBytes`. This is the regression net that lets us refactor without risking print output changes.
- **Imaging tests** — golden tests for orientation: known landscape and portrait source assets → expected `(width, height, rotation)` after auto-orientation. A handful of dither tests: flat-gray input → expected approximate black-pixel ratio.
- **Queue tests** — mock `PrinterClient` via a protocol; assert serial draining, status transitions, pause/resume, retry-then-auto-pause behavior.
- **No UI tests in v1.** Receipt printing is a hardware-feedback loop; dogfooding catches the issues UI automation would miss.

## Xcode setup

- New project: SwiftUI Multiplatform App template
- Bundle ID: `com.bryanelkus.peripage` (personal, not Atomic)
- Minimum deployment: iOS 17.0, macOS 14.0
- Destinations: iPhone, Mac (Designed for iPad/Mac)
- Capabilities: Bluetooth (entitlement on macOS sandbox; iOS uses Info.plist key only)
- No SPM/CocoaPods dependencies for v1

## Repo location

The Xcode project lives in this repo at `ios/` (the directory will hold both the iOS and macOS builds despite the name, since they share one target). This keeps the Python CLI tool and the app side-by-side, and the protocol-parity fixtures generated from `print_photo.py` stay trivially accessible to the Swift tests.

## Open items for the implementation plan

- Confirm the Apple Developer team ID at scaffold time (needed for signing)
- Confirm rotation direction (clockwise) is what's wanted for the auto-portrait case; flip if not
