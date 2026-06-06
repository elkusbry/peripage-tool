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
