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

    /// Invert each byte (white pixel bit → 0, black pixel bit → 1) so the
    /// printer fires its heating elements correctly. Input is raw
    /// MSB-first 1bpp packed bytes from a 576px-wide bitmap.
    public static func encodeImageToBytes(_ rawBits: Data) -> Data {
        Data(rawBits.map { $0 ^ 0xFF })
    }

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
}
