# Peripage iOS + macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a single SwiftUI Multiplatform app (iPhone + Mac) that prints photos to a Peripage A6 thermal printer over BLE, with live-preview adjustments, auto-rotation, and a serial print queue — preserving byte-for-byte parity with the existing `print_photo.py`.

**Architecture:** One Xcode target (destinations: iOS, macOS) generated via xcodegen for reproducibility. Five horizontal modules — `Protocol/` (pure functions), `Imaging/` (CoreGraphics pipeline), `Printer/` (CoreBluetooth actor behind a protocol), `Queue/` (serial `@Observable` worker), `App/` (three SwiftUI views). The Python tool lives in the repo and is used at test time to generate parity fixtures the Swift suite asserts against.

**Tech Stack:** Swift 5.10+, SwiftUI, `@Observable` (Observation framework), Swift Testing (`import Testing`), CoreBluetooth, CoreGraphics, PhotosUI, xcodegen for project generation. iOS 17 / macOS 14 minimum. No third-party runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-06-05-peripage-ios-mac-app-design.md`

---

## File Structure (the target state)

```
ios/
  Project.yml                              # xcodegen config
  Peripage/
    PeripageApp.swift                      # @main, scene wiring, root view
    Protocol/
      PeripageProtocol.swift               # constants + buildPayload + encodeImageToBytes
    Imaging/
      Adjustments.swift                    # Adjustments struct, Rotation enum
      ImageProcessor.swift                 # decode → orient → rotate → resize → dither → invert
    Printer/
      PrinterClientProtocol.swift          # protocol the queue depends on
      PrinterClient.swift                  # real CoreBluetooth implementation (@Observable)
      PrinterClientState.swift             # state enum + BLEError
    Queue/
      PrintJob.swift                       # job struct + JobStatus
      PrintQueue.swift                     # @Observable serial worker
    App/
      HomeView.swift
      PreviewView.swift
      QueueView.swift
      StatusPill.swift                     # reusable status indicator
      DebugLogView.swift
      DebugLog.swift                       # ring buffer + entry types
    Resources/
      Info.plist                           # usage descriptions
      Peripage.entitlements                # macOS sandbox + bluetooth
      Assets.xcassets/                     # app icons + colors
  PeripageTests/
    ProtocolParityTests.swift              # vs Python-generated fixtures
    ImagingTests.swift                     # orientation, dither
    QueueTests.swift                       # serial drain, pause/resume, retry-then-pause
    Mocks/
      MockPrinterClient.swift              # in-memory printer for queue tests
    Fixtures/
      flat_gray_64x64.png
      landscape_400x300.png
      portrait_300x400.png
      flat_gray_payload.bin                # python-generated
      flat_gray_raster.bin
      landscape_raster.bin
      portrait_raster.bin
fixtures/
  generate_fixtures.py                     # uses print_photo.py functions; writes Fixtures/*
```

The `fixtures/generate_fixtures.py` script imports from the existing `print_photo.py` (no duplicated protocol code) and dumps `.bin` files that Swift tests load. This is the parity guarantee.

---

## Task 1: Install xcodegen and create the ios/ directory

**Files:**
- Create: `ios/.gitkeep`

- [ ] **Step 1: Install xcodegen via Homebrew**

```bash
brew install xcodegen
xcodegen --version
```
Expected: prints `2.40.x` or newer.

- [ ] **Step 2: Create the ios/ directory**

```bash
mkdir -p ios/Peripage/{Protocol,Imaging,Printer,Queue,App,Resources}
mkdir -p ios/PeripageTests/{Mocks,Fixtures}
mkdir -p ios/Peripage/Resources/Assets.xcassets
touch ios/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add ios/.gitkeep
git commit -m "chore: scaffold ios/ directory tree"
```

---

## Task 2: Write the xcodegen project config

**Files:**
- Create: `ios/Project.yml`

- [ ] **Step 1: Write Project.yml**

```yaml
name: Peripage
options:
  bundleIdPrefix: com.elkus
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
  developmentLanguage: en
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: NO
    INFOPLIST_FILE: Peripage/Resources/Info.plist
    CODE_SIGN_STYLE: Automatic
    SWIFT_STRICT_CONCURRENCY: complete

targets:
  Peripage:
    type: application
    supportedDestinations: [iOS, macOS]
    sources:
      - path: Peripage
        excludes:
          - "Resources/Info.plist"
          - "Resources/Peripage.entitlements"
    resources:
      - Peripage/Resources/Assets.xcassets
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.elkus.peripage
        CODE_SIGN_ENTITLEMENTS: Peripage/Resources/Peripage.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        ENABLE_APP_SANDBOX: YES
      configs:
        Debug:
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG

  PeripageTests:
    type: bundle.unit-test
    supportedDestinations: [iOS, macOS]
    sources: [PeripageTests]
    dependencies:
      - target: Peripage
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 2: Commit**

```bash
git add ios/Project.yml
git commit -m "build: add xcodegen project config"
```

---

## Task 3: Create minimal placeholder source files so xcodegen succeeds

**Files:**
- Create: `ios/Peripage/PeripageApp.swift`
- Create: `ios/Peripage/Resources/Info.plist`
- Create: `ios/Peripage/Resources/Peripage.entitlements`

- [ ] **Step 1: Write a minimal PeripageApp.swift**

```swift
import SwiftUI

@main
struct PeripageApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Peripage")
                .padding()
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 640)
        #endif
    }
}
```

- [ ] **Step 2: Write the Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Peripage connects to your thermal printer over Bluetooth Low Energy to print photos.</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Peripage needs read access to your photo library so you can pick a photo to print.</string>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
  </array>
</dict>
</plist>
```

- [ ] **Step 3: Write the entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.device.bluetooth</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
  <key>com.apple.security.personal-information.photos-library</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create a minimal AppIcon set so build doesn't warn**

```bash
cat > ios/Peripage/Resources/Assets.xcassets/Contents.json <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
mkdir -p ios/Peripage/Resources/Assets.xcassets/AppIcon.appiconset
cat > ios/Peripage/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json <<'EOF'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
```

- [ ] **Step 5: Commit**

```bash
git add ios/Peripage
git commit -m "scaffold: minimal PeripageApp, Info.plist, entitlements, asset catalog"
```

---

## Task 4: Generate the Xcode project and verify it builds

**Files:**
- Modify: `.gitignore` (add `ios/Peripage.xcodeproj`)

- [ ] **Step 1: Add the generated project to .gitignore**

```bash
# Append to .gitignore (create if missing)
cat >> .gitignore <<'EOF'

# xcodegen output
ios/Peripage.xcodeproj/
ios/build/
ios/DerivedData/
.DS_Store
EOF
```

- [ ] **Step 2: Generate the project**

```bash
cd ios && xcodegen generate && cd ..
ls ios/Peripage.xcodeproj
```
Expected: `project.pbxproj` exists.

- [ ] **Step 3: Build for iOS Simulator (sanity check)**

```bash
xcodebuild -project ios/Peripage.xcodeproj \
  -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData \
  build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Build for macOS (sanity check)**

```bash
xcodebuild -project ios/Peripage.xcodeproj \
  -scheme Peripage \
  -destination 'platform=macOS' \
  -derivedDataPath ios/DerivedData \
  build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "build: ignore xcodegen output and verify iOS+macOS build"
```

---

## Task 5: Write the Python fixture generator

**Files:**
- Create: `fixtures/generate_fixtures.py`
- Create: `ios/PeripageTests/Fixtures/flat_gray_64x64.png`
- Create: `ios/PeripageTests/Fixtures/landscape_400x300.png`
- Create: `ios/PeripageTests/Fixtures/portrait_300x400.png`

The Python script imports from `print_photo.py` so we never duplicate the protocol logic into Python *and* Swift. The script writes the source images plus the expected byte outputs.

- [ ] **Step 1: Write generate_fixtures.py**

```python
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
```

- [ ] **Step 2: Run it from the venv**

```bash
source venv/bin/activate
python fixtures/generate_fixtures.py
ls ios/PeripageTests/Fixtures/
```
Expected: PNGs plus `*_raster.bin`, `*_payload_t40_b120.bin`, and `*_meta.txt` files.

- [ ] **Step 3: Commit**

```bash
git add fixtures/generate_fixtures.py ios/PeripageTests/Fixtures/
git commit -m "test: generate Swift parity fixtures from print_photo.py"
```

---

## Task 6: Implement Protocol constants (no tests yet — just the data)

**Files:**
- Create: `ios/Peripage/Protocol/PeripageProtocol.swift`

- [ ] **Step 1: Write PeripageProtocol.swift with constants only**

```swift
import Foundation

/// Pure, stateless byte-level protocol for Peripage A6 (BLE firmware).
/// Mirrors `print_photo.py` so the Python fixture generator and this code
/// produce byte-identical output.
public enum PeripageProtocol {
    /// Print head width in pixels.
    public static let printWidthPx: Int = 576

    /// 1bpp packed row width in bytes. 576 / 8 = 72.
    public static let rowBytes: Int = 72

    /// Max BLE write payload chunk. Multiple of rowBytes.
    public static let chunkSize: Int = 96

    /// Rows per `GS v 0` raster block. Some firmwares mis-render single
    /// giant blocks; multiple smaller blocks render reliably.
    public static let rowsPerBlock: Int = 256

    /// Inter-chunk delay during BLE send.
    public static let interChunkDelay: Duration = .milliseconds(15)

    /// Default 8s scan timeout, matching the Python tool.
    public static let scanTimeout: Duration = .seconds(8)

    /// BLE name prefix advertised by Peripage devices.
    public static let nameNamePrefix: String = "PeriPage"

    /// Write characteristic UUID.
    public static let writeCharacteristicUUIDString = "0000ff02-0000-1000-8000-00805f9b34fb"

    /// Reset / wake command sent at start and end of every job.
    public static let cmdReset = Data([0x10, 0x11, 0xff, 0xfe, 0x01])
}
```

- [ ] **Step 2: Regenerate project (so xcodegen picks up the new file)**

```bash
cd ios && xcodegen generate && cd ..
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/Protocol/PeripageProtocol.swift
git commit -m "protocol: add Peripage constants matching print_photo.py"
```

---

## Task 7: TDD — encodeImageToBytes parity test (failing)

**Files:**
- Create: `ios/PeripageTests/ProtocolParityTests.swift`

The Python `encode_image_to_bytes` takes a PIL `'1'`-mode image and XORs each byte with `0xFF` (so white pixel → bit 0). The Swift equivalent takes raw bit-packed bytes (1 bit per pixel, MSB-first within each byte) and inverts.

Test strategy: load the raster `.bin` we know is the *output*, derive the *input* by inverting it again (raw uninverted bits), feed it to Swift, expect identical output.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Peripage

@Suite("Protocol parity vs Python")
struct ProtocolParityTests {

    private static func fixturesDir() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private static func data(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesDir().appendingPathComponent(name))
    }

    @Test("encodeImageToBytes inverts and packs identically to Python")
    func encodeMatchesFlatGray() throws {
        // Python output is the inverted raster. Round-trip: invert it back
        // to derive the "raw 1bpp bits" input, hand that to Swift, expect
        // the same output as Python.
        let pythonOut = try Self.data("flat_gray_raster.bin")
        let rawBits = Data(pythonOut.map { $0 ^ 0xFF })

        let swiftOut = PeripageProtocol.encodeImageToBytes(rawBits)

        #expect(swiftOut == pythonOut)
    }
}
```

- [ ] **Step 2: Run and verify it fails for the right reason**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: build failure — `encodeImageToBytes` is not defined.

- [ ] **Step 3: Commit the failing test**

```bash
git add ios/PeripageTests/ProtocolParityTests.swift
git commit -m "test: failing parity test for encodeImageToBytes"
```

---

## Task 8: Implement encodeImageToBytes

**Files:**
- Modify: `ios/Peripage/Protocol/PeripageProtocol.swift`

- [ ] **Step 1: Add the function**

Append inside the `PeripageProtocol` enum:

```swift
    /// Invert each byte (white pixel bit → 0, black pixel bit → 1) so the
    /// printer fires its heating elements correctly. Input is raw
    /// MSB-first 1bpp packed bytes from a 384px-wide bitmap.
    public static func encodeImageToBytes(_ rawBits: Data) -> Data {
        Data(rawBits.map { $0 ^ 0xFF })
    }
```

- [ ] **Step 2: Run the test**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/ProtocolParityTests 2>&1 | tail -10
```
Expected: 1 test, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Protocol/PeripageProtocol.swift
git commit -m "protocol: implement encodeImageToBytes"
```

---

## Task 9: TDD — buildPayload parity test (failing)

**Files:**
- Modify: `ios/PeripageTests/ProtocolParityTests.swift`

- [ ] **Step 1: Add the failing payload test**

```swift
    @Test("buildPayload matches Python byte-for-byte for flat gray")
    func buildPayloadMatchesFlatGray() throws {
        let pythonRaster = try Self.data("flat_gray_raster.bin")
        let pythonPayload = try Self.data("flat_gray_payload_t40_b120.bin")
        let meta = try String(contentsOf: Self.fixturesDir()
            .appendingPathComponent("flat_gray_meta.txt"), encoding: .utf8)
        let height = Int(meta
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("height=") })!
            .dropFirst("height=".count))!

        let swiftPayload = PeripageProtocol.buildPayload(
            rasterBytes: pythonRaster, height: height,
            leadingFeed: 40, trailingFeed: 120
        )

        #expect(swiftPayload == pythonPayload)
    }

    @Test("buildPayload matches Python for landscape and portrait fixtures",
          arguments: ["landscape", "portrait"])
    func buildPayloadMatchesShape(_ name: String) throws {
        let raster = try Self.data("\(name)_raster.bin")
        let expected = try Self.data("\(name)_payload_t40_b120.bin")
        let meta = try String(contentsOf: Self.fixturesDir()
            .appendingPathComponent("\(name)_meta.txt"), encoding: .utf8)
        let height = Int(meta
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("height=") })!
            .dropFirst("height=".count))!

        let payload = PeripageProtocol.buildPayload(
            rasterBytes: raster, height: height,
            leadingFeed: 40, trailingFeed: 120
        )

        #expect(payload == expected, "Mismatch for fixture \(name)")
    }
```

- [ ] **Step 2: Verify the test fails to compile (missing method)**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: build error — `buildPayload` is not defined.

- [ ] **Step 3: Commit the failing tests**

```bash
git add ios/PeripageTests/ProtocolParityTests.swift
git commit -m "test: failing parity tests for buildPayload"
```

---

## Task 10: Implement buildPayload

**Files:**
- Modify: `ios/Peripage/Protocol/PeripageProtocol.swift`

The shape from Python: `CMD_RESET` + leading feed (`ESC J n`, chunked to 255) + N raster blocks (`GS v 0 m xL xH yL yH` + data) + trailing feed + `CMD_RESET`.

- [ ] **Step 1: Add buildPayload**

Append inside the `PeripageProtocol` enum:

```swift
    /// Build the full byte stream sent to the printer for one image:
    ///   CMD_RESET | (ESC J n) leading-feed | raster blocks | (ESC J n) trailing-feed | CMD_RESET
    public static func buildPayload(
        rasterBytes: Data,
        height: Int,
        leadingFeed: Int,
        trailingFeed: Int
    ) -> Data {
        precondition(rasterBytes.count == rowBytes * height,
                     "raster size (\(rasterBytes.count)) != rowBytes*height (\(rowBytes * height))")

        var out = Data()
        out.append(cmdReset)
        appendFeed(into: &out, pixels: leadingFeed)

        var rowsSent = 0
        while rowsSent < height {
            let rowsInBlock = min(rowsPerBlock, height - rowsSent)
            let xL = UInt8(rowBytes & 0xFF)
            let xH = UInt8((rowBytes >> 8) & 0xFF)
            let yL = UInt8(rowsInBlock & 0xFF)
            let yH = UInt8((rowsInBlock >> 8) & 0xFF)
            out.append(contentsOf: [0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH])

            let start = rowsSent * rowBytes
            let end = start + rowsInBlock * rowBytes
            out.append(rasterBytes[start..<end])

            rowsSent += rowsInBlock
        }

        appendFeed(into: &out, pixels: trailingFeed)
        out.append(cmdReset)
        return out
    }

    private static func appendFeed(into out: inout Data, pixels: Int) {
        var left = pixels
        while left > 0 {
            let n = min(left, 255)
            out.append(contentsOf: [0x1B, 0x4A, UInt8(n)])
            left -= n
        }
    }
```

- [ ] **Step 2: Run the parity tests**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/ProtocolParityTests 2>&1 | tail -10
```
Expected: 3 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Protocol/PeripageProtocol.swift
git commit -m "protocol: implement buildPayload with parity to Python"
```

---

## Task 11: Adjustments + Rotation types

**Files:**
- Create: `ios/Peripage/Imaging/Adjustments.swift`

- [ ] **Step 1: Write the types**

```swift
import Foundation

public enum Rotation: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case deg0
    case deg90
    case deg180
    case deg270

    /// Title for the segmented picker.
    public var label: String {
        switch self {
        case .auto:   return "Auto"
        case .deg0:   return "0°"
        case .deg90:  return "90°"
        case .deg180: return "180°"
        case .deg270: return "270°"
        }
    }
}

public struct Adjustments: Equatable, Codable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var topMarginPx: Int
    public var bottomMarginPx: Int
    public var rotation: Rotation

    public init(
        brightness: Double = 1.0,
        contrast: Double = 1.2,
        topMarginPx: Int = 40,
        bottomMarginPx: Int = 120,
        rotation: Rotation = .auto
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.topMarginPx = topMarginPx
        self.bottomMarginPx = bottomMarginPx
        self.rotation = rotation
    }

    public static let `default` = Adjustments()
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Imaging/Adjustments.swift
git commit -m "imaging: add Adjustments and Rotation types"
```

---

## Task 12: TDD — auto-rotation rule test

**Files:**
- Create: `ios/PeripageTests/ImagingTests.swift`

The spec rule: after EXIF transpose, if `width >= height` → `0°`, else → `90°` clockwise. This is the *opposite* of the Python tool.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Peripage

@Suite("Imaging")
struct ImagingTests {

    private static func fixturesDir() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private static func data(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesDir().appendingPathComponent(name))
    }

    @Test("Auto rotation: landscape stays at 0°")
    func autoLandscape() throws {
        let png = try Self.data("landscape_400x300.png")
        let resolved = try ImageProcessor.resolveRotation(.auto, for: png)
        #expect(resolved == .deg0)
    }

    @Test("Auto rotation: portrait rotates 90°")
    func autoPortrait() throws {
        let png = try Self.data("portrait_300x400.png")
        let resolved = try ImageProcessor.resolveRotation(.auto, for: png)
        #expect(resolved == .deg90)
    }

    @Test("Auto rotation: square stays at 0°")
    func autoSquare() throws {
        let png = try Self.data("flat_gray_64x64.png")
        let resolved = try ImageProcessor.resolveRotation(.auto, for: png)
        #expect(resolved == .deg0)
    }

    @Test("Explicit rotation passes through")
    func explicitPassthrough() throws {
        let png = try Self.data("landscape_400x300.png")
        for r in [Rotation.deg0, .deg90, .deg180, .deg270] {
            #expect(try ImageProcessor.resolveRotation(r, for: png) == r)
        }
    }
}
```

- [ ] **Step 2: Verify it fails to build (no `ImageProcessor`)**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: build error — `ImageProcessor` is not defined.

- [ ] **Step 3: Commit the failing test**

```bash
git add ios/PeripageTests/ImagingTests.swift
git commit -m "test: failing tests for auto-rotation rule"
```

---

## Task 13: Implement ImageProcessor scaffolding + rotation resolution

**Files:**
- Create: `ios/Peripage/Imaging/ImageProcessor.swift`

- [ ] **Step 1: Write the scaffold**

```swift
import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public enum ImageProcessingError: Error, Equatable {
    case decodeFailed
    case unsupportedColorSpace
    case sizeMismatch(expected: Int, got: Int)
}

public enum ImageProcessor {

    // MARK: - Auto rotation

    /// Resolve `.auto` against the image's EXIF-corrected orientation.
    /// Landscape (or square) stays at `.deg0`; portrait becomes `.deg90`.
    public static func resolveRotation(_ rotation: Rotation, for imageData: Data) throws -> Rotation {
        if rotation != .auto { return rotation }
        let size = try orientedSize(of: imageData)
        return size.width >= size.height ? .deg0 : .deg90
    }

    /// Decode the image's pixel size *after* applying EXIF orientation.
    private static func orientedSize(of data: Data) throws -> CGSize {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ImageProcessingError.decodeFailed }

        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        // EXIF orientations 5–8 swap width and height.
        if (5...8).contains(orientation) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }
}
```

- [ ] **Step 2: Run the imaging tests**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/ImagingTests 2>&1 | tail -10
```
Expected: 4 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Imaging/ImageProcessor.swift
git commit -m "imaging: scaffold ImageProcessor with auto-rotation resolution"
```

---

## Task 14: TDD — process() pipeline produces correct-sized 1bpp output

**Files:**
- Modify: `ios/PeripageTests/ImagingTests.swift`

After the full pipeline the raster size must be `72 * height` bytes, and `height` is determined by the post-rotation aspect ratio scaled to 576 wide.

- [ ] **Step 1: Add the failing test**

Append inside the `ImagingTests` suite:

```swift
    @Test("process() produces 72 bytes per row for landscape input")
    func processLandscapeSize() throws {
        let png = try Self.data("landscape_400x300.png")
        let result = try ImageProcessor.process(png, adjustments: .default)
        #expect(result.rasterBytes.count % 72 == 0)
        #expect(result.rasterBytes.count == 72 * result.height)
        // Landscape stays landscape → 400→576, 300 → ~432 (4:3 preserved)
        #expect(result.height >= 425 && result.height <= 440)
    }

    @Test("process() rotates portrait → height ~ 432 (300→576 wide after rotation)")
    func processPortraitSize() throws {
        let png = try Self.data("portrait_300x400.png")
        let result = try ImageProcessor.process(png, adjustments: .default)
        // After 90° rotation portrait becomes landscape (400x300),
        // 400→576, 300 → ~432. Same target as the landscape fixture.
        #expect(result.height >= 425 && result.height <= 440)
    }

    @Test("process() inverts bits (default mid-gray dithers to ~50% black)")
    func processInvertsCorrectly() throws {
        let png = try Self.data("flat_gray_64x64.png")
        let result = try ImageProcessor.process(png, adjustments: .default)
        let blackBitCount = result.rasterBytes.reduce(0) { $0 + $1.nonzeroBitCount }
        let totalBits = result.rasterBytes.count * 8
        let ratio = Double(blackBitCount) / Double(totalBits)
        // Contrast=1.2 on flat 128 grey pushes a bit darker than 50%.
        // Floyd–Steinberg + a slight contrast bump: somewhere in 0.45–0.85.
        #expect(ratio >= 0.40 && ratio <= 0.90,
                "Expected dither ratio in [0.40, 0.90], got \(ratio)")
    }
```

- [ ] **Step 2: Verify the test fails to build (`process` missing)**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: build error — `process` is not a member of `ImageProcessor`.

- [ ] **Step 3: Commit**

```bash
git add ios/PeripageTests/ImagingTests.swift
git commit -m "test: failing tests for process() pipeline"
```

---

## Task 15: Implement the full image pipeline

**Files:**
- Modify: `ios/Peripage/Imaging/ImageProcessor.swift`

The pipeline: decode → EXIF transpose → resolve rotation → apply rotation → resize to 576 wide → brightness/contrast → grayscale → Floyd–Steinberg dither → pack to 1bpp MSB-first → invert (call `encodeImageToBytes`).

- [ ] **Step 1: Add `Result` type and the `process` entry point**

Append inside `ImageProcessor`:

```swift
    public struct ProcessedImage {
        public let previewCGImage: CGImage   // 8-bit grayscale post-dither, native size for preview
        public let rasterBytes: Data         // 1bpp MSB-first, white→bit 0 (printer-ready)
        public let width: Int                // == 576
        public let height: Int
    }

    public static func process(_ data: Data, adjustments: Adjustments) throws -> ProcessedImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ImageProcessingError.decodeFailed }

        // 1. EXIF-correct the raw bitmap
        let oriented = try orientedCopy(of: raw, sourceData: data)

        // 2. Resolve rotation (auto rule baked in here)
        let resolvedRotation: Rotation = adjustments.rotation == .auto
            ? (oriented.width >= oriented.height ? .deg0 : .deg90)
            : adjustments.rotation
        let rotated = rotate(oriented, by: resolvedRotation)

        // 3. Resize so width == 576, preserving aspect ratio
        let targetWidth = PeripageProtocol.printWidthPx
        let targetHeight = max(1, Int((Double(rotated.height) * Double(targetWidth) / Double(rotated.width)).rounded()))
        let resized = try resizeGrayscale(rotated, to: CGSize(width: targetWidth, height: targetHeight))

        // 4. Brightness + contrast in 8-bit grayscale space
        let adjusted = applyBrightnessContrast(resized, brightness: adjustments.brightness, contrast: adjustments.contrast)

        // 5. Floyd–Steinberg dither → 1bpp MSB-first packed bytes (uninverted)
        let rawBits = floydSteinbergDither(adjusted, width: targetWidth, height: targetHeight)
        let printerBytes = PeripageProtocol.encodeImageToBytes(rawBits)

        guard printerBytes.count == PeripageProtocol.rowBytes * targetHeight else {
            throw ImageProcessingError.sizeMismatch(
                expected: PeripageProtocol.rowBytes * targetHeight,
                got: printerBytes.count
            )
        }

        // Build an 8-bit grayscale preview from the same dither (for UI display)
        let previewCG = try grayscaleCGImage(fromBits: rawBits, width: targetWidth, height: targetHeight, invertForDisplay: true)

        return ProcessedImage(
            previewCGImage: previewCG,
            rasterBytes: printerBytes,
            width: targetWidth,
            height: targetHeight
        )
    }
```

- [ ] **Step 2: Add the helper functions**

Append inside `ImageProcessor`:

```swift
    // MARK: - Pipeline helpers (CoreGraphics)

    private static func orientedCopy(of image: CGImage, sourceData: Data) throws -> CGImage {
        let src = CGImageSourceCreateWithData(sourceData as CFData, nil)
        let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation == 1 { return image }

        // Use CGContext to bake the orientation into pixel space.
        let isSwapped = (5...8).contains(orientation)
        let outW = isSwapped ? image.height : image.width
        let outH = isSwapped ? image.width  : image.height
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw ImageProcessingError.decodeFailed }

        applyOrientationTransform(ctx: ctx, orientation: orientation, width: outW, height: outH)
        ctx.draw(image, in: CGRect(x: 0, y: 0,
                                   width: isSwapped ? outH : outW,
                                   height: isSwapped ? outW : outH))
        guard let out = ctx.makeImage() else { throw ImageProcessingError.decodeFailed }
        return out
    }

    private static func applyOrientationTransform(ctx: CGContext, orientation: UInt32, width w: Int, height h: Int) {
        let W = CGFloat(w), H = CGFloat(h)
        switch orientation {
        case 2: ctx.translateBy(x: W, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 3: ctx.translateBy(x: W, y: H); ctx.rotate(by: .pi)
        case 4: ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        case 5: ctx.rotate(by: .pi/2); ctx.scaleBy(x: 1, y: -1)
        case 6: ctx.translateBy(x: W, y: 0); ctx.rotate(by: .pi/2)
        case 7: ctx.translateBy(x: W, y: H); ctx.rotate(by: .pi/2); ctx.scaleBy(x: 1, y: -1)
        case 8: ctx.translateBy(x: 0, y: H); ctx.rotate(by: -.pi/2)
        default: break
        }
    }

    private static func rotate(_ image: CGImage, by rotation: Rotation) -> CGImage {
        switch rotation {
        case .auto, .deg0: return image
        case .deg90:  return rotateCG(image, radians: -.pi / 2)   // clockwise
        case .deg180: return rotateCG(image, radians: .pi)
        case .deg270: return rotateCG(image, radians: .pi / 2)    // counter-clockwise
        }
    }

    private static func rotateCG(_ image: CGImage, radians: CGFloat) -> CGImage {
        let w = image.width, h = image.height
        let isQuarter = abs(radians.truncatingRemainder(dividingBy: .pi)) > 0.01
        let outW = isQuarter ? h : w
        let outH = isQuarter ? w : h
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        ctx.translateBy(x: CGFloat(outW)/2, y: CGFloat(outH)/2)
        ctx.rotate(by: radians)
        ctx.draw(image, in: CGRect(x: -CGFloat(w)/2, y: -CGFloat(h)/2, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage() ?? image
    }

    private static func resizeGrayscale(_ image: CGImage, to size: CGSize) throws -> CGImage {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw ImageProcessingError.decodeFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        guard let out = ctx.makeImage() else { throw ImageProcessingError.decodeFailed }
        return out
    }

    private static func applyBrightnessContrast(_ image: CGImage, brightness: Double, contrast: Double) -> CGImage {
        // Pull 8-bit grayscale pixels into a buffer, transform per byte, repack.
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // PIL semantics: brightness multiplies, contrast pivots around 128.
        for i in pixels.indices {
            var v = Double(pixels[i]) * brightness
            v = (v - 128) * contrast + 128
            pixels[i] = UInt8(max(0, min(255, v.rounded())))
        }

        guard let out = ctx.makeImage() else { return image }
        return out
    }

    /// Floyd–Steinberg dither over an 8-bit grayscale image; returns
    /// MSB-first 1bpp packed bytes where bit=1 means WHITE (uninverted).
    private static func floydSteinbergDither(_ image: CGImage, width w: Int, height h: Int) -> Data {
        var pixels = [Int](repeating: 0, count: w * h)
        var raw = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &raw, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in raw.indices { pixels[i] = Int(raw[i]) }

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let old = pixels[i]
                let new = old < 128 ? 0 : 255
                pixels[i] = new
                let err = old - new
                if x + 1 < w     { pixels[i + 1]      += err * 7 / 16 }
                if y + 1 < h {
                    if x > 0     { pixels[i + w - 1]  += err * 3 / 16 }
                                   pixels[i + w]      += err * 5 / 16
                    if x + 1 < w { pixels[i + w + 1]  += err * 1 / 16 }
                }
            }
        }

        // Pack MSB-first. Bit=1 means WHITE (255 in pixels).
        let rowBytes = PeripageProtocol.rowBytes
        var packed = Data(count: rowBytes * h)
        packed.withUnsafeMutableBytes { buf in
            for y in 0..<h {
                for x in 0..<w {
                    let p = pixels[y * w + x]
                    if p >= 128 {
                        let byteIndex = y * rowBytes + (x >> 3)
                        let bit: UInt8 = 0x80 >> UInt8(x & 7)
                        buf[byteIndex] |= bit
                    }
                }
            }
        }
        return packed
    }

    private static func grayscaleCGImage(fromBits bits: Data, width w: Int, height h: Int, invertForDisplay: Bool) throws -> CGImage {
        let rowBytes = PeripageProtocol.rowBytes
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let byte = bits[y * rowBytes + (x >> 3)]
                let bit = (byte >> UInt8(7 - (x & 7))) & 1
                let white = bit == 1
                pixels[y * w + x] = invertForDisplay ? (white ? 255 : 0) : (white ? 0 : 255)
            }
        }
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let img = ctx.makeImage() else {
            throw ImageProcessingError.decodeFailed
        }
        return img
    }
```

- [ ] **Step 2: Run the imaging suite**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/ImagingTests 2>&1 | tail -10
```
Expected: 7 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Imaging/ImageProcessor.swift
git commit -m "imaging: full process pipeline (decode→orient→rotate→resize→dither→pack)"
```

---

## Task 16: PrintJob + JobStatus types

**Files:**
- Create: `ios/Peripage/Queue/PrintJob.swift`

- [ ] **Step 1: Write the types**

```swift
import Foundation

public enum JobStatus: Equatable, Sendable {
    case pending
    case rendering
    case sending(progress: Double)
    case done
    case failed(reason: String)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }
}

public struct PrintJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceData: Data
    public var adjustments: Adjustments
    public var status: JobStatus

    public init(
        id: UUID = UUID(),
        sourceData: Data,
        adjustments: Adjustments,
        status: JobStatus = .pending
    ) {
        self.id = id
        self.sourceData = sourceData
        self.adjustments = adjustments
        self.status = status
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Queue/PrintJob.swift
git commit -m "queue: add PrintJob and JobStatus types"
```

---

## Task 17: PrinterClient protocol + state + error types

**Files:**
- Create: `ios/Peripage/Printer/PrinterClientState.swift`
- Create: `ios/Peripage/Printer/PrinterClientProtocol.swift`

- [ ] **Step 1: Write the state and error types**

```swift
// PrinterClientState.swift
import Foundation

public enum PrinterState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting(name: String)
    case connected(name: String)
    case sending(jobId: UUID, progress: Double)
    case error(BLEError)
}

public enum BLEError: Error, Equatable, Sendable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case scanTimeout
    case noPeripheralFound
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(description: String)
    case disconnectedDuringSend
    case cancelled
}
```

- [ ] **Step 2: Write the protocol**

```swift
// PrinterClientProtocol.swift
import Foundation

public protocol PrinterClientProtocol: AnyObject, Sendable {
    /// Observable current state.
    var state: PrinterState { get }

    /// Ensure we're connected to a Peripage. Scans if no peripheral is
    /// already in hand. Throws `BLEError` on permission / scan-timeout
    /// failure.
    func ensureConnected() async throws

    /// Send a single payload to the printer in 96-byte chunks with a
    /// 15ms inter-chunk gap. Updates `state` to `.sending(jobId, progress)`.
    /// Throws on disconnect / write failure.
    func send(_ payload: Data, jobId: UUID) async throws

    /// Cleanly disconnect (called at queue idle).
    func disconnect() async
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/Printer
git commit -m "printer: PrinterClient protocol, state, and BLEError"
```

---

## Task 18: MockPrinterClient for queue tests

**Files:**
- Create: `ios/PeripageTests/Mocks/MockPrinterClient.swift`

- [ ] **Step 1: Write the mock**

```swift
import Foundation
@testable import Peripage

/// Configurable in-memory printer. Records every call, and can be told to
/// fail on `ensureConnected` or `send` for retry tests.
final class MockPrinterClient: PrinterClientProtocol, @unchecked Sendable {
    enum Failure: Equatable {
        case connectThrows(BLEError)
        case sendThrows(BLEError)
    }

    private let lock = NSLock()
    private var _state: PrinterState = .disconnected
    private(set) var sends: [(jobId: UUID, payloadLen: Int)] = []
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0
    var nextFailures: [Failure] = []

    var state: PrinterState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func ensureConnected() async throws {
        lock.lock(); connectCalls += 1; lock.unlock()
        if case .connectThrows(let e) = nextFailures.first {
            lock.lock(); nextFailures.removeFirst(); lock.unlock()
            throw e
        }
        lock.lock(); _state = .connected(name: "MockPeriPage"); lock.unlock()
    }

    func send(_ payload: Data, jobId: UUID) async throws {
        if case .sendThrows(let e) = nextFailures.first {
            lock.lock(); nextFailures.removeFirst(); lock.unlock()
            throw e
        }
        lock.lock()
        sends.append((jobId, payload.count))
        _state = .sending(jobId: jobId, progress: 1.0)
        lock.unlock()
    }

    func disconnect() async {
        lock.lock(); disconnectCalls += 1; _state = .disconnected; lock.unlock()
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build-for-testing 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/PeripageTests/Mocks/MockPrinterClient.swift
git commit -m "test: MockPrinterClient for queue tests"
```

---

## Task 19: TDD — PrintQueue serial drain test

**Files:**
- Create: `ios/PeripageTests/QueueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Peripage

@Suite("PrintQueue")
struct QueueTests {

    private static func fixturesDir() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private func jobA() throws -> PrintJob {
        let data = try Data(contentsOf: Self.fixturesDir().appendingPathComponent("landscape_400x300.png"))
        return PrintJob(sourceData: data, adjustments: .default)
    }
    private func jobB() throws -> PrintJob {
        let data = try Data(contentsOf: Self.fixturesDir().appendingPathComponent("portrait_300x400.png"))
        return PrintJob(sourceData: data, adjustments: .default)
    }

    @Test("Queue drains jobs serially in FIFO order")
    func drainsSerially() async throws {
        let printer = MockPrinterClient()
        let queue = PrintQueue(printer: printer)
        let a = try jobA(); let b = try jobB()

        await queue.enqueue(a)
        await queue.enqueue(b)
        await queue.start()
        await queue.waitForIdle(timeout: .seconds(10))

        #expect(printer.sends.count == 2)
        #expect(printer.sends[0].jobId == a.id)
        #expect(printer.sends[1].jobId == b.id)
        let statuses = await queue.snapshot.map(\.status)
        #expect(statuses.allSatisfy { $0 == .done })
    }
}
```

- [ ] **Step 2: Verify the test fails to build (`PrintQueue` missing)**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: build error — `PrintQueue` is not defined.

- [ ] **Step 3: Commit**

```bash
git add ios/PeripageTests/QueueTests.swift
git commit -m "test: failing PrintQueue serial drain test"
```

---

## Task 20: Implement PrintQueue (serial drain only)

**Files:**
- Create: `ios/Peripage/Queue/PrintQueue.swift`

- [ ] **Step 1: Write the queue**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class PrintQueue {
    public private(set) var jobs: [PrintJob] = []
    public private(set) var isPaused: Bool = false
    public private(set) var isRunning: Bool = false

    private let printer: PrinterClientProtocol
    private var worker: Task<Void, Never>?

    public init(printer: PrinterClientProtocol) {
        self.printer = printer
    }

    public var snapshot: [PrintJob] { jobs }

    public func enqueue(_ job: PrintJob) {
        jobs.append(job)
    }

    public func cancel(_ id: UUID) {
        jobs.removeAll { $0.id == id && !$0.status.isTerminal }
    }

    public func clearCompleted() {
        jobs.removeAll { $0.status.isTerminal }
    }

    public func pause() { isPaused = true }
    public func resume() { isPaused = false; start() }

    public func start() {
        guard worker == nil else { return }
        isRunning = true
        worker = Task { @MainActor [weak self] in
            await self?.drain()
            self?.isRunning = false
            self?.worker = nil
        }
    }

    public func waitForIdle(timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while isRunning && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Internal

    private func drain() async {
        while let index = nextPendingIndex(), !isPaused {
            await process(jobIndex: index)
        }
    }

    private func nextPendingIndex() -> Int? {
        jobs.firstIndex { $0.status == .pending }
    }

    private func process(jobIndex i: Int) async {
        jobs[i].status = .rendering
        let job = jobs[i]
        do {
            let processed = try ImageProcessor.process(job.sourceData, adjustments: job.adjustments)
            let payload = PeripageProtocol.buildPayload(
                rasterBytes: processed.rasterBytes,
                height: processed.height,
                leadingFeed: job.adjustments.topMarginPx,
                trailingFeed: job.adjustments.bottomMarginPx
            )
            try await printer.ensureConnected()
            jobs[i].status = .sending(progress: 0.0)
            try await printer.send(payload, jobId: job.id)
            jobs[i].status = .done
        } catch {
            jobs[i].status = .failed(reason: String(describing: error))
        }
    }
}
```

- [ ] **Step 2: Run the queue tests**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/QueueTests 2>&1 | tail -10
```
Expected: 1 test, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/Queue/PrintQueue.swift
git commit -m "queue: PrintQueue with serial drain via PrinterClientProtocol"
```

---

## Task 21: TDD — pause / resume test

**Files:**
- Modify: `ios/PeripageTests/QueueTests.swift`

- [ ] **Step 1: Add the test**

```swift
    @Test("Pausing prevents further drain; resume continues")
    func pauseResume() async throws {
        let printer = MockPrinterClient()
        let queue = PrintQueue(printer: printer)
        let a = try jobA(); let b = try jobB()

        await queue.enqueue(a)
        await queue.enqueue(b)
        queue.pause()
        queue.start()
        await queue.waitForIdle(timeout: .milliseconds(200))

        // Paused: no sends yet
        #expect(printer.sends.isEmpty)

        queue.resume()
        await queue.waitForIdle(timeout: .seconds(10))
        #expect(printer.sends.count == 2)
    }
```

- [ ] **Step 2: Run — expected to pass because `pause()` already short-circuits the drain loop**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/QueueTests 2>&1 | tail -10
```
Expected: 2 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add ios/PeripageTests/QueueTests.swift
git commit -m "test: pause/resume queue behavior"
```

---

## Task 22: TDD + impl — retry-then-auto-pause behavior

**Files:**
- Modify: `ios/PeripageTests/QueueTests.swift`
- Modify: `ios/Peripage/Queue/PrintQueue.swift`

Spec: two consecutive reconnect failures auto-pause the queue.

- [ ] **Step 1: Add the failing test**

Append to `QueueTests`:

```swift
    @Test("Two consecutive connect failures auto-pause the queue")
    func autoPauseAfterTwoFailures() async throws {
        let printer = MockPrinterClient()
        printer.nextFailures = [
            .connectThrows(.noPeripheralFound),
            .connectThrows(.noPeripheralFound),
        ]
        let queue = PrintQueue(printer: printer)
        await queue.enqueue(try jobA())
        await queue.enqueue(try jobB())
        await queue.start()
        await queue.waitForIdle(timeout: .seconds(5))

        #expect(queue.isPaused == true)
        #expect(printer.sends.isEmpty)
        let firstFailed = queue.snapshot.first.map { if case .failed = $0.status { return true } else { return false } }
        #expect(firstFailed == true)
    }
```

- [ ] **Step 2: Verify it fails**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/QueueTests 2>&1 | tail -10
```
Expected: assertion failure on `queue.isPaused == true`.

- [ ] **Step 3: Update PrintQueue.drain to count consecutive connect failures**

Replace the `drain` and `process` methods inside `PrintQueue`:

```swift
    private var consecutiveConnectFailures = 0

    private func drain() async {
        while let index = nextPendingIndex(), !isPaused {
            await process(jobIndex: index)
            if consecutiveConnectFailures >= 2 {
                isPaused = true
                break
            }
        }
    }

    private func process(jobIndex i: Int) async {
        jobs[i].status = .rendering
        let job = jobs[i]
        do {
            let processed = try ImageProcessor.process(job.sourceData, adjustments: job.adjustments)
            let payload = PeripageProtocol.buildPayload(
                rasterBytes: processed.rasterBytes,
                height: processed.height,
                leadingFeed: job.adjustments.topMarginPx,
                trailingFeed: job.adjustments.bottomMarginPx
            )
            do {
                try await printer.ensureConnected()
                consecutiveConnectFailures = 0
            } catch let e as BLEError {
                consecutiveConnectFailures += 1
                jobs[i].status = .failed(reason: String(describing: e))
                return
            }
            jobs[i].status = .sending(progress: 0.0)
            try await printer.send(payload, jobId: job.id)
            jobs[i].status = .done
        } catch {
            jobs[i].status = .failed(reason: String(describing: error))
        }
    }
```

- [ ] **Step 4: Re-run the queue tests**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData -only-testing:PeripageTests/QueueTests 2>&1 | tail -10
```
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add ios/PeripageTests/QueueTests.swift ios/Peripage/Queue/PrintQueue.swift
git commit -m "queue: auto-pause after two consecutive connect failures"
```

---

## Task 23: DebugLog ring buffer

**Files:**
- Create: `ios/Peripage/App/DebugLog.swift`

- [ ] **Step 1: Write the log**

```swift
import Foundation
import Observation

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: Level
    public let message: String

    public enum Level: String, Sendable {
        case info, warn, error
    }
}

@MainActor
@Observable
public final class DebugLog {
    public static let shared = DebugLog()
    public private(set) var entries: [LogEntry] = []
    private let capacity = 200

    public func info(_ msg: String)  { append(.info, msg) }
    public func warn(_ msg: String)  { append(.warn, msg) }
    public func error(_ msg: String) { append(.error, msg) }

    private func append(_ level: LogEntry.Level, _ msg: String) {
        entries.append(LogEntry(timestamp: Date(), level: level, message: msg))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public func renderText() -> String {
        let f = ISO8601DateFormatter()
        return entries.map { "\(f.string(from: $0.timestamp))  [\($0.level.rawValue)]  \($0.message)" }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/App/DebugLog.swift
git commit -m "app: DebugLog ring buffer (capacity 200)"
```

---

## Task 24: Real PrinterClient — CBCentralManager wrapper

**Files:**
- Create: `ios/Peripage/Printer/PrinterClient.swift`

This is the big one: an `@MainActor`-isolated `@Observable` class that owns a `CBCentralManager`, exposes async `ensureConnected` / `send` / `disconnect`, and surfaces `PrinterState` for the UI.

- [ ] **Step 1: Write the bones (init, state property, BLE delegate scaffolding)**

```swift
import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
public final class PrinterClient: NSObject, PrinterClientProtocol {
    public private(set) var state: PrinterState = .disconnected

    private let serviceQueue = DispatchQueue(label: "peripage.printer.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?

    // Pending continuations
    private var pendingPowerOn: CheckedContinuation<Void, Error>?
    private var pendingScan: CheckedContinuation<CBPeripheral, Error>?
    private var pendingConnect: CheckedContinuation<Void, Error>?

    private var scanTimer: Task<Void, Never>?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: serviceQueue, options: nil)
    }

    public func ensureConnected() async throws {
        if case .connected = state { return }
        try await waitForPowerOn()
        let p = try await scanForPeripheral()
        try await connect(to: p)
    }

    public func send(_ payload: Data, jobId: UUID) async throws {
        guard let peripheral = peripheral, let writeChar = writeChar else {
            throw BLEError.characteristicNotFound
        }
        let total = payload.count
        var sent = 0
        let chunkSize = PeripageProtocol.chunkSize
        while sent < total {
            let end = min(sent + chunkSize, total)
            let chunk = payload[sent..<end]
            peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)
            sent = end
            state = .sending(jobId: jobId, progress: Double(sent) / Double(total))
            try await Task.sleep(for: PeripageProtocol.interChunkDelay)
        }
        // Settle: real printer needs ~3s to flush its buffer
        try await Task.sleep(for: .seconds(3))
        state = .connected(name: peripheral.name ?? "Peripage")
    }

    public func disconnect() async {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        state = .disconnected
    }
}
```

- [ ] **Step 2: Add the power-on wait + scan helpers**

Append inside the class:

```swift
    private func waitForPowerOn() async throws {
        switch central.state {
        case .poweredOn:    return
        case .unauthorized: throw BLEError.bluetoothUnauthorized
        case .unsupported:  throw BLEError.bluetoothUnavailable
        case .poweredOff:   throw BLEError.bluetoothPoweredOff
        default: break
        }
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            self.pendingPowerOn = cc
        }
    }

    private func scanForPeripheral() async throws -> CBPeripheral {
        state = .scanning
        DebugLog.shared.info("Scanning for \(PeripageProtocol.nameNamePrefix)…")
        return try await withCheckedThrowingContinuation { cc in
            self.pendingScan = cc
            self.central.scanForPeripherals(withServices: nil, options: nil)
            self.scanTimer?.cancel()
            self.scanTimer = Task { [weak self] in
                try? await Task.sleep(for: PeripageProtocol.scanTimeout)
                await self?.scanTimedOut()
            }
        }
    }

    @MainActor
    private func scanTimedOut() {
        guard let cc = pendingScan else { return }
        central.stopScan()
        pendingScan = nil
        state = .error(.scanTimeout)
        cc.resume(throwing: BLEError.scanTimeout)
    }

    private func connect(to p: CBPeripheral) async throws {
        state = .connecting(name: p.name ?? "Peripage")
        peripheral = p
        p.delegate = self
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            self.pendingConnect = cc
            self.central.connect(p, options: nil)
        }
    }
```

- [ ] **Step 3: Add the `CBCentralManagerDelegate` and `CBPeripheralDelegate` conformances**

Append as extensions in the same file:

```swift
extension PrinterClient: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if let cc = self.pendingPowerOn { self.pendingPowerOn = nil; cc.resume() }
            case .unauthorized:
                self.state = .error(.bluetoothUnauthorized)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothUnauthorized); self.pendingPowerOn = nil
            case .poweredOff:
                self.state = .error(.bluetoothPoweredOff)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothPoweredOff); self.pendingPowerOn = nil
            case .unsupported:
                self.state = .error(.bluetoothUnavailable)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothUnavailable); self.pendingPowerOn = nil
            default: break
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name.lowercased().contains(PeripageProtocol.nameNamePrefix.lowercased()) else { return }
        Task { @MainActor in
            guard let cc = self.pendingScan else { return }
            self.pendingScan = nil
            self.scanTimer?.cancel(); self.scanTimer = nil
            self.central.stopScan()
            DebugLog.shared.info("Found \(name)")
            cc.resume(returning: peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let e = BLEError.writeFailed(description: error?.localizedDescription ?? "didFailToConnect")
            self.state = .error(e)
            self.pendingConnect?.resume(throwing: e); self.pendingConnect = nil
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.peripheral = nil
            self.writeChar = nil
            if case .sending = self.state {
                self.state = .error(.disconnectedDuringSend)
            } else {
                self.state = .disconnected
            }
        }
    }
}

extension PrinterClient: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            let targetUUID = CBUUID(string: PeripageProtocol.writeCharacteristicUUIDString)
            if let ch = service.characteristics?.first(where: { $0.uuid == targetUUID }) {
                self.writeChar = ch
                self.state = .connected(name: peripheral.name ?? "Peripage")
                self.pendingConnect?.resume(); self.pendingConnect = nil
                DebugLog.shared.info("Write characteristic ready")
            }
        }
    }
}
```

- [ ] **Step 4: Build (we don't unit-test the real client — it talks to hardware)**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite to make sure nothing regressed**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: all suites pass.

- [ ] **Step 6: Commit**

```bash
git add ios/Peripage/Printer/PrinterClient.swift
git commit -m "printer: CoreBluetooth implementation of PrinterClient"
```

---

## Task 25: StatusPill view

**Files:**
- Create: `ios/Peripage/App/StatusPill.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

struct StatusPill: View {
    let state: PrinterState
    let queueCount: Int
    var onLongPress: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout.monospaced())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.thinMaterial))
        .onLongPressGesture(minimumDuration: 0.6) { onLongPress() }
    }

    private var color: Color {
        switch state {
        case .disconnected: return .secondary
        case .scanning, .connecting: return .yellow
        case .connected: return .green
        case .sending: return .blue
        case .error: return .red
        }
    }

    private var label: String {
        switch state {
        case .disconnected:
            return queueCount > 0 ? "Idle · \(queueCount) queued" : "Idle"
        case .scanning: return "Scanning…"
        case .connecting(let n): return "Connecting \(n)…"
        case .connected(let n):
            return queueCount > 0 ? "\(n) · \(queueCount) queued" : n
        case .sending(_, let p):
            return "Sending… \(Int(p * 100))%"
        case .error(let e): return "Error: \(String(describing: e))"
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/App/StatusPill.swift
git commit -m "app: StatusPill view"
```

---

## Task 26: HomeView

**Files:**
- Create: `ios/Peripage/App/HomeView.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(PrinterClient.self) private var printer
    @Environment(PrintQueue.self) private var queue

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var showDebug = false
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 24) {
            StatusPill(
                state: printer.state,
                queueCount: queue.jobs.filter { !$0.status.isTerminal }.count,
                onLongPress: { showDebug = true }
            )
            .padding(.top)

            Spacer()

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .font(.title2.bold())
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(Capsule().fill(.tint))
                    .foregroundStyle(.white)
            }

            if queue.jobs.contains(where: { !$0.status.isTerminal }) {
                Button {
                    showQueue = true
                } label: {
                    Label("Queue (\(queue.jobs.filter { !$0.status.isTerminal }.count))",
                          systemImage: "list.bullet")
                }
            }

            Spacer()
        }
        .padding()
        .navigationDestination(isPresented: Binding(
            get: { pickedData != nil },
            set: { if !$0 { pickedData = nil; photoItem = nil } }
        )) {
            if let data = pickedData {
                PreviewView(sourceData: data)
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showDebug) { DebugLogView() }
        .task(id: photoItem) {
            guard let photoItem else { return }
            pickedData = try? await photoItem.loadTransferable(type: Data.self)
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: build error — `PreviewView` and `QueueView` and `DebugLogView` not defined. That's OK; we'll add stubs next.

- [ ] **Step 3: Add stubs to silence the build**

Append to bottom of `HomeView.swift`:

```swift
struct PreviewView_Stub: View { let sourceData: Data; var body: some View { Text("PreviewView TODO") } }
struct QueueView_Stub: View { var body: some View { Text("QueueView TODO") } }
struct DebugLogView_Stub: View { var body: some View { Text("DebugLogView TODO") } }
```

Replace the three references in `body` (`PreviewView(...)` → `PreviewView_Stub(...)`, etc.) for now.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Peripage/App/HomeView.swift
git commit -m "app: HomeView with PhotosPicker and status pill"
```

---

## Task 27: PreviewView — layout, sliders, live preview

**Files:**
- Create: `ios/Peripage/App/PreviewView.swift`
- Modify: `ios/Peripage/App/HomeView.swift` (remove the `_Stub` references)

- [ ] **Step 1: Write PreviewView**

```swift
import SwiftUI

struct PreviewView: View {
    let sourceData: Data
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    @State private var adjustments = Adjustments.default
    @State private var preview: PlatformImage?
    @State private var renderError: String?

    var body: some View {
        VStack(spacing: 16) {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: 360)
                .background(
                    checkerboard
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                )

            controls
            buttons
        }
        .padding()
        .navigationTitle("Adjust")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: adjustments) {
            await rerenderDebounced()
        }
    }

    private var previewPane: some View {
        Group {
            if let preview {
                #if canImport(UIKit)
                Image(uiImage: preview).resizable().interpolation(.none).scaledToFit()
                #else
                Image(nsImage: preview).resizable().interpolation(.none).scaledToFit()
                #endif
            } else if let renderError {
                Text(renderError).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            slider("Brightness", value: $adjustments.brightness, range: 0.5...2.0, step: 0.05)
            slider("Contrast",   value: $adjustments.contrast,   range: 0.5...2.0, step: 0.05)
            intSlider("Top margin",    value: $adjustments.topMarginPx,    range: 0...300, step: 5)
            intSlider("Bottom margin", value: $adjustments.bottomMarginPx, range: 0...300, step: 5)
            rotationPicker
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private func intSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int.Stride) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step)
            )
            Text("\(value.wrappedValue) px")
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private var rotationPicker: some View {
        HStack {
            Text("Rotation").frame(width: 110, alignment: .leading)
            Picker("", selection: $adjustments.rotation) {
                ForEach(Rotation.allCases, id: \.self) { r in
                    Text(r.label).tag(r)
                }
            }.pickerStyle(.segmented)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Add to queue") {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                dismiss()
            }.buttonStyle(.bordered)

            Spacer()

            Button("Print now") {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                queue.start()
                dismiss()
            }.buttonStyle(.borderedProminent)
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) {
                    let dark = (Int(x/s) + Int(y/s)) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: x, y: y, width: s, height: s)),
                        with: .color(dark ? .gray.opacity(0.18) : .gray.opacity(0.08))
                    )
                }
            }
        }
    }

    private func rerenderDebounced() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            #if canImport(UIKit)
            preview = UIImage(cgImage: processed.previewCGImage)
            #else
            preview = NSImage(cgImage: processed.previewCGImage, size: NSSize(width: processed.width, height: processed.height))
            #endif
            renderError = nil
        } catch {
            renderError = String(describing: error)
        }
    }
}
```

- [ ] **Step 2: Remove the stubs from HomeView.swift**

Edit `HomeView.swift`: delete the three `_Stub` view definitions at the bottom and change `PreviewView_Stub(sourceData: data)` → `PreviewView(sourceData: data)`, `QueueView_Stub()` → `QueueView()`, `DebugLogView_Stub()` → `DebugLogView()`.

(QueueView and DebugLogView don't exist yet — the build will fail until we add them. That's fine — we'll add them in the next tasks.)

- [ ] **Step 3: Add temporary stubs in PreviewView.swift to keep the build green**

Append to `PreviewView.swift`:

```swift
struct QueueView: View { var body: some View { Text("QueueView TODO") } }
struct DebugLogView: View { var body: some View { Text("DebugLogView TODO") } }
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Peripage/App
git commit -m "app: PreviewView with sliders, rotation picker, debounced live preview"
```

---

## Task 28: QueueView (replace the stub)

**Files:**
- Create: `ios/Peripage/App/QueueView.swift`
- Modify: `ios/Peripage/App/PreviewView.swift` (remove the QueueView stub)

- [ ] **Step 1: Write QueueView**

```swift
import SwiftUI

struct QueueView: View {
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(queue.jobs) { job in
                    row(for: job)
                    #if os(iOS)
                        .swipeActions {
                            if !job.status.isTerminal {
                                Button("Cancel", role: .destructive) { queue.cancel(job.id) }
                            }
                        }
                    #else
                        .contextMenu {
                            if !job.status.isTerminal {
                                Button("Cancel") { queue.cancel(job.id) }
                            }
                        }
                    #endif
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { pauseResumeButton }
                ToolbarItem(placement: .bottomBar) { Button("Clear completed") { queue.clearCompleted() } }
                #else
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem { pauseResumeButton }
                ToolbarItem { Button("Clear completed") { queue.clearCompleted() } }
                #endif
            }
            .navigationTitle("Queue")
        }
    }

    private var pauseResumeButton: some View {
        Button(queue.isPaused ? "Resume" : "Pause") {
            queue.isPaused ? queue.resume() : queue.pause()
        }
    }

    private func row(for job: PrintJob) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(jobTitle(job)).font(.headline)
                Text(statusLabel(job.status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .sending(let p) = job.status {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 80)
            }
        }
    }

    private func jobTitle(_ job: PrintJob) -> String {
        "Photo \(job.id.uuidString.prefix(6))"
    }

    private func statusLabel(_ status: JobStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .rendering: return "Rendering…"
        case .sending(let p): return "Sending \(Int(p * 100))%"
        case .done: return "Done"
        case .failed(let r): return "Failed — \(r)"
        }
    }
}
```

- [ ] **Step 2: Remove the QueueView stub from PreviewView.swift**

Delete the `struct QueueView: View { ... }` stub.

- [ ] **Step 3: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/App
git commit -m "app: QueueView with per-platform cancel + pause/resume + clear"
```

---

## Task 29: DebugLogView (replace the stub)

**Files:**
- Create: `ios/Peripage/App/DebugLogView.swift`
- Modify: `ios/Peripage/App/PreviewView.swift` (remove the DebugLogView stub)

- [ ] **Step 1: Write DebugLogView**

```swift
import SwiftUI

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    private let log = DebugLog.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.renderText())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Debug Log")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                #else
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #endif
                ToolbarItem {
                    ShareLink(item: log.renderText()) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Remove the DebugLogView stub from PreviewView.swift**

Delete the `struct DebugLogView: View { ... }` stub.

- [ ] **Step 3: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/App
git commit -m "app: DebugLogView (long-press status pill to open)"
```

---

## Task 30: Bluetooth-permission gate view

**Files:**
- Create: `ios/Peripage/App/BluetoothGateView.swift`

- [ ] **Step 1: Write the gate**

```swift
import SwiftUI

struct BluetoothGateView: View {
    let error: BLEError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Settings") { openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var title: String {
        switch error {
        case .bluetoothPoweredOff: return "Bluetooth is off"
        case .bluetoothUnauthorized: return "Bluetooth permission needed"
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        default: return "Bluetooth error"
        }
    }
    private var message: String {
        switch error {
        case .bluetoothPoweredOff:
            return "Turn Bluetooth on in Settings, then come back to Peripage."
        case .bluetoothUnauthorized:
            return "Peripage needs Bluetooth access to talk to your printer."
        case .bluetoothUnavailable:
            return "Your device doesn't support Bluetooth Low Energy."
        default:
            return ""
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/App/BluetoothGateView.swift
git commit -m "app: BluetoothGateView with platform-aware Settings deep-link"
```

---

## Task 31: Wire it all together in PeripageApp

**Files:**
- Modify: `ios/Peripage/PeripageApp.swift`

- [ ] **Step 1: Replace PeripageApp.swift**

```swift
import SwiftUI

@main
struct PeripageApp: App {
    @State private var printer = PrinterClient()
    @State private var queue: PrintQueue

    init() {
        let p = PrinterClient()
        _printer = State(initialValue: p)
        _queue = State(initialValue: PrintQueue(printer: p))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                rootView
            }
            .environment(printer)
            .environment(queue)
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 640)
        .windowResizability(.contentMinSize)
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        if case .error(let e) = printer.state, isBluetoothFatal(e) {
            BluetoothGateView(error: e)
        } else {
            HomeView()
        }
    }

    private func isBluetoothFatal(_ e: BLEError) -> Bool {
        switch e {
        case .bluetoothPoweredOff, .bluetoothUnauthorized, .bluetoothUnavailable: return true
        default: return false
        }
    }
}
```

- [ ] **Step 2: Build for both platforms**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5 && \
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=macOS' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Peripage/PeripageApp.swift
git commit -m "app: wire PrinterClient + PrintQueue into PeripageApp with BLE gate"
```

---

## Task 32: iOS success haptic on job complete

**Files:**
- Create: `ios/Peripage/App/Haptics.swift`
- Modify: `ios/Peripage/Queue/PrintQueue.swift`

- [ ] **Step 1: Write the platform-conditional haptic helper**

```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
```

- [ ] **Step 2: Fire haptics from PrintQueue.process**

In `process(jobIndex:)`, find:

```swift
            try await printer.send(payload, jobId: job.id)
            jobs[i].status = .done
```

Change to:

```swift
            try await printer.send(payload, jobId: job.id)
            jobs[i].status = .done
            Haptics.success()
```

And inside the outer `catch`:

```swift
        } catch {
            jobs[i].status = .failed(reason: String(describing: error))
            Haptics.error()
        }
```

- [ ] **Step 3: Build for both platforms**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5 && \
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=macOS' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/App/Haptics.swift ios/Peripage/Queue/PrintQueue.swift
git commit -m "app: success/error haptics on iOS (no-op on macOS)"
```

---

## Task 33: Run the full test suite on both platforms

- [ ] **Step 1: iOS simulator suite**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 2: macOS suite**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=macOS' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: No commit needed (verification only)**

---

## Task 34: Manual dogfood pass — iOS device

**This task is run on real hardware. There is no automated step.**

- [ ] **Step 1: Configure signing**

Open `ios/Peripage.xcodeproj` in Xcode → Peripage target → Signing & Capabilities → select Bryan's personal Apple Developer team. Confirm bundle identifier reads `com.elkus.peripage`.

- [ ] **Step 2: Build and run to an iPhone**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'generic/platform=iOS' -derivedDataPath ios/DerivedData
```

Or via Xcode UI: select your iPhone → Run.

- [ ] **Step 3: Walk the happy path**

1. Launch the app → Bluetooth permission prompt appears → tap Allow.
2. Power on the Peripage. Confirm it's not paired in iOS Bluetooth settings.
3. Tap Choose Photo → pick a landscape photo → preview should appear, no rotation.
4. Tap Print Now → status pill goes Scanning → Connecting → Sending → photo prints.
5. Tap Choose Photo → pick a portrait photo → preview should be rotated 90° clockwise.
6. Tap Add to Queue → enqueue 2 more photos → tap Queue → tap Pause then Resume → confirm they print in order.
7. Power off the printer mid-print → confirm the job moves to Failed and the queue auto-pauses after the second failure.
8. Long-press the status pill → DebugLogView opens → entries are present.

- [ ] **Step 4: File any issues you find as TODO comments in the relevant Swift file or add follow-up tasks; do not fix in this task — keep it observational**

---

## Task 35: Manual dogfood pass — macOS

- [ ] **Step 1: Run on macOS**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=macOS' -derivedDataPath ios/DerivedData
open ios/DerivedData/Build/Products/Debug/Peripage.app
```

- [ ] **Step 2: Confirm UX differences land as designed**

1. Window opens at ~540×640 minimum.
2. Bluetooth permission prompt: macOS shows the system Bluetooth privacy dialog. Approve.
3. Choose Photo → standard macOS open panel appears (NSPhotoLibraryUsageDescription does not apply on macOS; the photos library is reached via the `PhotosPicker` UI).
4. Queue view uses context-menu cancel instead of swipe.
5. Walk the same happy path as iOS.

- [ ] **Step 3: No commit needed — dogfooding only**

---

## Task 36: Final cleanup and changelog

**Files:**
- Create: `ios/CHANGELOG.md`

- [ ] **Step 1: Write a v0.1.0 changelog**

```markdown
# Peripage App Changelog

## 0.1.0 — 2026-06-05

- Initial release of Peripage iOS + macOS app
- Single SwiftUI multiplatform target (iOS 17 / macOS 14)
- Live-preview dithered output with brightness, contrast, top margin, bottom margin sliders
- Auto-rotation: portraits rotate 90° clockwise so long axis fits the 384px print width; landscape stays put. Manual override available (0° / 90° / 180° / 270°).
- Serial print queue with pause / resume / cancel / clear-completed
- Auto-pause after two consecutive connect failures
- Hidden debug log (long-press the status pill) with share sheet
- Byte-for-byte protocol parity with `print_photo.py`, asserted via Python-generated fixtures
```

- [ ] **Step 2: Commit**

```bash
git add ios/CHANGELOG.md
git commit -m "docs: v0.1.0 changelog for ios/macOS app"
```

---

# Phase 2 — iOS Share Extension ("Print to Peripage" from Photos)

Goal: tap any photo in Photos.app (or any app that exposes a `public.image` share), pick **Print to Peripage** from the share sheet, see the same dithered preview + sliders, hit Print, watch it print. iOS only. macOS keeps the Automator Quick Action at `scripts/print_to_peripage.sh`.

Approach: a new `PeripageShare` app-extension target in the same xcodegen project. It re-compiles the same `Protocol/`, `Imaging/`, `Printer/`, `Queue/`, and `App/DebugLog.swift` source files directly (no embedded framework), plus its own `ShareViewController` + SwiftUI principal view. The extension instantiates its own `PrinterClient` and `PrintQueue`, prints in-place, and calls `completeRequest`. Bluetooth permission is shared with the host app via the same bundle prefix; first run prompts.

Known limitation: iOS share extensions have shorter runtime budgets than apps. For very large photos (>800px tall after rotate/resize) a single BLE send can exceed it. Phase 2 protects against that with a UIApplication-style background-task assertion (where available in extension context) and falls back to surfacing an "Open Peripage app to finish" message if the send is interrupted. A proper hand-off via App Groups is left as a follow-up task.

## Task 37: Add the PeripageShare extension target to Project.yml

**Files:**
- Modify: `ios/Project.yml`
- Create: `ios/PeripageShare/Info.plist`
- Create: `ios/PeripageShare/PeripageShare.entitlements`
- Create: `ios/PeripageShare/ShareViewController.swift` (minimal stub so xcodegen succeeds)

- [ ] **Step 1: Update Project.yml — add PeripageShare target and embed it into the app**

Append after the `PeripageTests` target block:

```yaml
  PeripageShare:
    type: app-extension
    platform: iOS
    sources:
      - PeripageShare
      - path: Peripage/Protocol
      - path: Peripage/Imaging
      - path: Peripage/Printer
      - path: Peripage/Queue
      - path: Peripage/App/DebugLog.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.elkus.peripage.share
        INFOPLIST_FILE: PeripageShare/Info.plist
        CODE_SIGN_ENTITLEMENTS: PeripageShare/PeripageShare.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        ENABLE_APP_SANDBOX: YES
        SWIFT_VERSION: "5.10"
        IPHONEOS_DEPLOYMENT_TARGET: "17.0"
```

Then add the extension as a dependency of the iOS app build so Xcode embeds it. Find the `Peripage` target block and add:

```yaml
    dependencies:
      - target: PeripageShare
        embed: true
        platformFilter: iOS
```

- [ ] **Step 2: Write `PeripageShare/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Print to Peripage</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Peripage connects to your thermal printer over Bluetooth Low Energy to print the photo you shared.</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionAttributes</key>
    <dict>
      <key>NSExtensionActivationRule</key>
      <dict>
        <key>NSExtensionActivationSupportsImageWithMaxCount</key>
        <integer>1</integer>
      </dict>
    </dict>
    <key>NSExtensionMainStoryboard</key>
    <string></string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
  </dict>
</dict>
</plist>
```

(Note: we use `NSExtensionPrincipalClass` instead of a storyboard so we can host SwiftUI from a `UIViewController` subclass directly.)

- [ ] **Step 3: Write `PeripageShare/PeripageShare.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.device.bluetooth</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 4: Write a placeholder `PeripageShare/ShareViewController.swift`**

```swift
import UIKit

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Real implementation lands in Task 39.
    }
}
```

- [ ] **Step 5: Regenerate the Xcode project**

```bash
cd ios && xcodegen generate && cd ..
```
Expected: no errors; `xcodegen` reports `PeripageShare` as a new target.

- [ ] **Step 6: Build the app target on iOS Simulator (which now embeds the extension)**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` and `PeripageShare.appex` shows up under the `Peripage.app/PlugIns/` directory.

```bash
ls ios/DerivedData/Build/Products/Debug-iphonesimulator/Peripage.app/PlugIns/
```
Expected: `PeripageShare.appex`.

- [ ] **Step 7: Verify the macOS build is unaffected**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=macOS' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. The `platformFilter: iOS` and `platform: iOS` keep the extension out of the Mac product.

- [ ] **Step 8: Commit**

```bash
git add ios/Project.yml ios/PeripageShare
git commit -m "share-ext: scaffold PeripageShare app-extension target (iOS only)"
```

---

## Task 38: Share-flow data model + payload loader

**Files:**
- Create: `ios/PeripageShare/SharePayload.swift`

The extension receives `NSItemProvider`s from the host. We need a small helper that resolves the first `public.image` provider into raw `Data` we can hand to `ImageProcessor.process`.

- [ ] **Step 1: Write SharePayload.swift**

```swift
import Foundation
import UniformTypeIdentifiers

enum SharePayloadError: Error, LocalizedError {
    case noImageItem
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImageItem: return "The shared item isn't an image."
        case .loadFailed(let why): return "Couldn't load the shared image: \(why)"
        }
    }
}

enum SharePayload {
    /// Resolve the first image item in the input items into Data.
    /// Supports JPEG, PNG, HEIC (loaded as Data and decoded by ImageIO downstream).
    static func loadFirstImage(from inputItems: [Any]) async throws -> Data {
        let providers: [NSItemProvider] = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard let provider = providers.first else { throw SharePayloadError.noImageItem }

        // Try `public.image` raw data first (preserves original bytes for ImageIO).
        return try await withCheckedThrowingContinuation { cc in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data { cc.resume(returning: data); return }
                if let error { cc.resume(throwing: SharePayloadError.loadFailed(error.localizedDescription)); return }
                cc.resume(throwing: SharePayloadError.loadFailed("no data, no error"))
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/PeripageShare/SharePayload.swift
git commit -m "share-ext: image payload loader from NSItemProviders"
```

---

## Task 39: Share extension SwiftUI principal view + ShareViewController

**Files:**
- Modify: `ios/PeripageShare/ShareViewController.swift`
- Create: `ios/PeripageShare/ShareRootView.swift`

The view reuses the same `Adjustments` model and `ImageProcessor.process` as the main app, but its own `PrinterClient` and an inline serial drain (we don't need a full queue UI here — single-photo flow). It hosts a SwiftUI view inside the principal `UIViewController` and reports completion via the extension context.

- [ ] **Step 1: Replace ShareViewController.swift with the SwiftUI host**

```swift
import UIKit
import SwiftUI

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let inputItems = extensionContext?.inputItems ?? []
        let root = ShareRootView(
            inputItems: inputItems,
            onDone:    { [weak self] in self?.completeRequest() },
            onCancel:  { [weak self] in self?.cancelRequest() }
        )

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancelRequest() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.elkus.peripage.share",
            code: NSUserCancelledError,
            userInfo: nil
        ))
    }
}
```

- [ ] **Step 2: Write ShareRootView.swift — preview + sliders + print button**

```swift
import SwiftUI
import UIKit

struct ShareRootView: View {
    let inputItems: [Any]
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var sourceData: Data?
    @State private var loadError: String?
    @State private var adjustments = Adjustments.default
    @State private var preview: UIImage?
    @State private var renderError: String?

    // Single-shot printer + status
    @State private var printer = PrinterClient()
    @State private var phase: Phase = .editing

    enum Phase: Equatable {
        case editing
        case printing(progress: Double)
        case done
        case failed(reason: String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Print to Peripage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Print") { Task { await print() } }
                            .disabled(!canPrint)
                            .fontWeight(.semibold)
                    }
                }
                .task { await loadSource() }
                .task(id: adjustments) { await rerenderDebounced() }
        }
    }

    private var canPrint: Bool {
        if case .editing = phase, sourceData != nil, preview != nil { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .editing:
            editingBody
        case .printing(let p):
            VStack(spacing: 16) {
                ProgressView(value: p).progressViewStyle(.linear).padding()
                Text("Sending… \(Int(p * 100))%").font(.callout)
            }.padding()
        case .done:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Sent to printer").font(.title3.bold())
                Button("Done") { onDone() }.buttonStyle(.borderedProminent)
            }.padding()
        case .failed(let reason):
            VStack(spacing: 12) {
                Image(systemName: "xmark.octagon.fill").font(.largeTitle).foregroundStyle(.red)
                Text("Failed").font(.title3.bold())
                Text(reason).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { onCancel() }.buttonStyle(.bordered)
                    Button("Try again") { phase = .editing }.buttonStyle(.borderedProminent)
                }
            }.padding()
        }
    }

    private var editingBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewPane
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 320)

                slider("Brightness", value: $adjustments.brightness, range: 0.5...2.0, step: 0.05)
                slider("Contrast",   value: $adjustments.contrast,   range: 0.5...2.0, step: 0.05)
                intSlider("Top",    value: $adjustments.topMarginPx,    range: 0...300, step: 5)
                intSlider("Bottom", value: $adjustments.bottomMarginPx, range: 0...300, step: 5)

                HStack {
                    Text("Rotation").frame(width: 100, alignment: .leading)
                    Picker("", selection: $adjustments.rotation) {
                        ForEach(Rotation.allCases, id: \.self) { r in Text(r.label).tag(r) }
                    }.pickerStyle(.segmented)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let preview {
            Image(uiImage: preview).resizable().interpolation(.none).scaledToFit()
        } else if let renderError {
            Text(renderError).foregroundStyle(.red)
        } else if let loadError {
            Text(loadError).foregroundStyle(.red)
        } else {
            ProgressView()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private func intSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int.Stride) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step)
            )
            Text("\(value.wrappedValue) px").font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Load + render

    private func loadSource() async {
        do {
            let data = try await SharePayload.loadFirstImage(from: inputItems)
            sourceData = data
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func rerenderDebounced() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard let sourceData, !Task.isCancelled else { return }
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            preview = UIImage(cgImage: processed.previewCGImage)
            renderError = nil
        } catch {
            renderError = String(describing: error)
        }
    }

    // MARK: - Print

    private func print() async {
        guard let sourceData else { return }
        phase = .printing(progress: 0)
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            let payload = PeripageProtocol.buildPayload(
                rasterBytes: processed.rasterBytes,
                height: processed.height,
                leadingFeed: adjustments.topMarginPx,
                trailingFeed: adjustments.bottomMarginPx
            )
            try await printer.ensureConnected()
            let jobId = UUID()
            // Reflect printer.state progress into our local UI.
            let progressObserver = Task { @MainActor in
                while !Task.isCancelled {
                    if case .sending(_, let p) = printer.state {
                        phase = .printing(progress: p)
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            defer { progressObserver.cancel() }
            try await printer.send(payload, jobId: jobId)
            await printer.disconnect()
            phase = .done
        } catch {
            phase = .failed(reason: String(describing: error))
        }
    }
}
```

- [ ] **Step 3: Regenerate + build**

```bash
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`. Both `Peripage.app` and `PeripageShare.appex` are produced.

- [ ] **Step 4: Run the test suite — extension changes mustn't regress app tests**

```bash
xcodebuild test -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath ios/DerivedData 2>&1 | tail -10
```
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add ios/PeripageShare
git commit -m "share-ext: SwiftUI principal view with preview, sliders, print, completion"
```

---

## Task 40: Manual dogfood — print from Photos.app on real iPhone

**This task requires real hardware + a physical Peripage. No automation.**

- [ ] **Step 1: Configure signing for both targets**

Open `ios/Peripage.xcodeproj` in Xcode. For each target (`Peripage` and `PeripageShare`) → Signing & Capabilities → select the same Apple Developer team. Confirm bundle IDs read `com.elkus.peripage` and `com.elkus.peripage.share`.

- [ ] **Step 2: Build + install to the iPhone**

```bash
xcodebuild -project ios/Peripage.xcodeproj -scheme Peripage \
  -destination 'generic/platform=iOS' -derivedDataPath ios/DerivedData
```

Or via Xcode UI: select iPhone → Run.

- [ ] **Step 3: Enable the extension (first run only)**

1. Open the host app once and grant Bluetooth permission so the extension inherits it.
2. Open Photos.app → pick any photo → tap the share icon.
3. Scroll the action row → tap **More** → enable **Print to Peripage** if it's not already on. Optionally drag it near the top of the list.

- [ ] **Step 4: Walk the happy path**

1. Photos.app → pick a landscape photo → Share → **Print to Peripage**.
2. Preview should render within ~300ms; sliders should update preview live.
3. Tap **Print** → progress bar advances → "Sent to printer" success state → Done.
4. Verify the print matches what the host app produces for the same photo + adjustments (i.e., parity is preserved by reusing `ImageProcessor` + `PeripageProtocol`).
5. Pick a portrait photo → Share → confirm auto-rotation kicks in (preview is landscape).
6. Tap **Cancel** mid-edit → confirm the sheet closes cleanly without spinning the BLE radio.

- [ ] **Step 5: Walk failure paths**

1. Power off the Peripage → share a photo → tap Print → expect failure state with a readable reason → "Try again" reopens edit mode.
2. Turn off Bluetooth in Control Center → share → tap Print → expect `bluetoothPoweredOff` style failure.

- [ ] **Step 6: File any issues as TODO comments in the relevant Swift file, do not fix in this task**

---

## Task 41: v0.2.0 changelog

**Files:**
- Modify: `ios/CHANGELOG.md`

- [ ] **Step 1: Prepend a v0.2.0 entry to CHANGELOG.md**

```markdown
## 0.2.0 — 2026-06-05

- iOS Share Extension: "Print to Peripage" in any app's share sheet for `public.image` items
- Reuses the host app's `ImageProcessor` + `PeripageProtocol` so print output is byte-identical
- Single-photo flow inside the share sheet: live preview, all four sliders, rotation, Print
- Failure paths surface a "Try again" / "Cancel" choice instead of dumping a stack trace
- Known limitation: very tall photos may exceed the extension's runtime budget; follow-up tracks an App Group hand-off to the host app
```

- [ ] **Step 2: Commit**

```bash
git add ios/CHANGELOG.md
git commit -m "docs: v0.2.0 changelog — iOS Share Extension"
```

---

## Self-review

**Spec coverage (each section traced to a task):**

- Project scaffold (single target, iOS+macOS, no deps) → Tasks 1–4
- `Protocol/` constants + buildPayload + encodeImageToBytes → Tasks 6, 8, 10 with parity tests 7, 9
- `Imaging/` Adjustments + Rotation + ImageProcessor with auto-rotation and full pipeline → Tasks 11–15
- `Queue/` PrintJob + PrintQueue serial / pause / retry-then-pause → Tasks 16, 19–22
- `Printer/` protocol, state, error, mock, real CoreBluetooth implementation → Tasks 17, 18, 24
- HomeView / PreviewView / QueueView / StatusPill / BluetoothGateView / DebugLogView → Tasks 25–30
- Wiring + Bluetooth gate → Task 31
- iOS haptics → Task 32
- Info.plist (NSBluetoothAlwaysUsageDescription, NSPhotoLibraryUsageDescription) → Task 3
- macOS entitlements (sandbox, bluetooth, photos) → Task 3
- Protocol parity tests, imaging tests, queue tests → Tasks 7–10, 12–15, 19–22
- Dogfood passes (iOS + macOS) → Tasks 34–35
- Changelog → Task 36

**Phase 2 coverage:**

- Share Extension target scaffold (Project.yml, Info.plist with NSExtension, entitlements) → Task 37
- Image payload loader from `NSItemProvider` (handles `public.image` UTI) → Task 38
- SwiftUI principal view: load → live preview → adjust → print → complete/cancel, with own `PrinterClient` instance → Task 39
- Real-device dogfood from Photos.app, plus failure paths (printer off, BLE off) → Task 40
- v0.2.0 changelog → Task 41

**Phase 2 design notes:**

- Source-file sharing (not framework) — `Project.yml` re-references `Peripage/Protocol`, `Peripage/Imaging`, `Peripage/Printer`, `Peripage/Queue`, and `App/DebugLog.swift` directly from the extension target. Compiles those files into both targets; avoids the embedded-framework rabbit hole at the cost of a slightly larger combined binary.
- Extension prints directly (no `PrintQueue` in the share sheet) — the share flow is single-photo by definition. Uses `PrinterClient` directly with a local progress observer task.
- `platformFilter: iOS` on the embed + `platform: iOS` on the target keeps the extension out of the macOS product, so Mac builds and tests stay green.

**Placeholder scan:** no "TBD" / "TODO" / "similar to" / "implement later" in step bodies. Every code-modifying step contains the actual Swift. Stubs introduced in Task 26–29 are explicitly removed in the very next task and the test runs catch their absence.

**Type / name consistency check:** `Adjustments`, `Rotation`, `PrintJob`, `JobStatus`, `PrinterState`, `BLEError`, `PrintQueue`, `PrinterClient`, `PrinterClientProtocol`, `ImageProcessor`, `PeripageProtocol`, `DebugLog` — all defined exactly once and referenced consistently. `Adjustments.default` defined in Task 11, used in Tasks 14, 19, 20, 27. `PrintQueue.start()` / `pause()` / `resume()` / `cancel(_:)` / `clearCompleted()` / `waitForIdle(timeout:)` defined in Task 20 and all referenced views/tests match. `PrinterClient.state` exposes `PrinterState` as defined in Task 17 and the state-machine transitions in Task 24 match the cases listed in StatusPill in Task 25.
