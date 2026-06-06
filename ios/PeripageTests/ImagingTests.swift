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
}
