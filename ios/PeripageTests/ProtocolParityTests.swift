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
