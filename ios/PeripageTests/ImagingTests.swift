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

    @Test("Auto rotation: landscape source rotates 90°")
    func autoLandscape() throws {
        let png = try Self.data("landscape_400x300.png")
        let resolved = try ImageProcessor.resolveRotation(.auto, for: png)
        #expect(resolved == .deg90)
    }

    @Test("Auto rotation: portrait source stays at 0°")
    func autoPortrait() throws {
        let png = try Self.data("portrait_300x400.png")
        let resolved = try ImageProcessor.resolveRotation(.auto, for: png)
        #expect(resolved == .deg0)
    }

    @Test("Auto rotation: square source stays at 0°")
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

    @Test("process() rotates landscape 90° → tall output (~768 rows)")
    func processLandscapeSize() throws {
        let png = try Self.data("landscape_400x300.png")
        let result = try ImageProcessor.process(png, adjustments: .default)
        #expect(result.rasterBytes.count % 72 == 0)
        #expect(result.rasterBytes.count == 72 * result.height)
        // Landscape 400×300 → rotate 90° CW → 300×400 → scale to width 576 → 768 tall.
        #expect(result.height >= 760 && result.height <= 776)
    }

    @Test("process() keeps portrait at 0° → tall output (~768 rows)")
    func processPortraitSize() throws {
        let png = try Self.data("portrait_300x400.png")
        let result = try ImageProcessor.process(png, adjustments: .default)
        // Portrait 300×400 stays portrait → scale to width 576 → 768 tall.
        #expect(result.height >= 760 && result.height <= 776)
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
}
