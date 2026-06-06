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
