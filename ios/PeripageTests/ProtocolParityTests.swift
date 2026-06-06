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
}
