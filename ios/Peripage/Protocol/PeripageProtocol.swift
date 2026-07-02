import Foundation

/// Pure, stateless byte-level protocol for Peripage A6 (BLE firmware).
/// Mirrors `print_photo.py` so the Python fixture generator and this code
/// produce byte-identical output.
public enum PeripageProtocol {
    /// Print head width in pixels.
    public static let printWidthPx: Int = 576

    /// 1bpp packed row width in bytes. 576 / 8 = 72.
    public static let rowBytes: Int = 72

    /// Minimum / fallback BLE write payload chunk. The actual chunk size is the
    /// negotiated MTU clamped to `maxChunkSize`, but never below this (see
    /// `PrinterClient.send`).
    public static let chunkSize: Int = 96

    /// Ceiling on the per-write chunk. Modern iPhones negotiate an ATT MTU of
    /// 180–244 payload bytes; using MTU-sized writes means ~2.5× fewer
    /// `writeValue` calls (less MainActor jitter, fewer stall windows) at the
    /// SAME byte rate the printer sees. Cap it so a large negotiated MTU can't
    /// produce a pathologically big single write. If overrun ever appears
    /// (shifted image), lower this. Chunk size need NOT align to rowBytes — the
    /// printer reassembles the byte stream.
    public static let maxChunkSize: Int = 244

    /// Target delivery rate to the print head, in bytes/second. This is the
    /// real pacing invariant (was expressed as 96 B / 12 ms = 8.0 KB/s ≈ 111
    /// rows/s vs the head's ~89 rows/s, 25% headroom). The per-chunk delay is
    /// derived from this and the actual chunk size, so changing the chunk size
    /// does not change the rate. Transport pacing only — NOT part of the payload
    /// and NOT covered by the parity fixtures, so it can be retuned freely. If
    /// underrun gaps appear (blank bands), raise the rate slightly; if overrun
    /// appears (shifted image), lower it.
    public static let targetBytesPerSecond: Double = 8000

    /// Legacy fixed inter-chunk interval, retained for reference. No longer used
    /// by the send loop, which derives its delay from `targetBytesPerSecond`.
    public static let interChunkDelay: Duration = .milliseconds(12)

    /// If deadline pacing falls this far behind (e.g. a long MainActor stall),
    /// re-anchor the schedule so the catch-up burst stays bounded (~12 chunks)
    /// instead of slamming the printer's receive path.
    public static let maxPacingBacklog: Duration = .milliseconds(150)

    /// Default 8s scan timeout, matching the Python tool.
    public static let scanTimeout: Duration = .seconds(8)

    /// Physical print-head throughput, in raster rows per second. Used to
    /// compute the post-send drain wait: the head still needs
    /// `height / headRowsPerSecond` to physically print, and the paced send
    /// already overlaps most of that. Documented at ~89 rows/s.
    public static let headRowsPerSecond: Double = 89

    /// Safety padding added to the computed drain so we never disconnect (the
    /// firmware's commit signal) while the head is still finishing the tail.
    public static let drainSafetyMargin: Duration = .milliseconds(750)

    /// Clamp bounds for the computed drain wait. Floor keeps a tiny print from
    /// disconnecting instantly; ceiling prevents a hang if the estimate is off.
    public static let minDrain: Duration = .milliseconds(500)
    public static let maxDrain: Duration = .seconds(6)

    /// BLE name prefix advertised by Peripage devices.
    public static let nameNamePrefix: String = "PeriPage"

    /// GATT service holding the FF01/FF02/FF03 characteristics. Used to scope
    /// service/characteristic discovery instead of walking the whole GATT table.
    public static let serviceUUIDString = "FF00"

    /// Write characteristic UUID.
    public static let writeCharacteristicUUIDString = "0000ff02-0000-1000-8000-00805f9b34fb"

    /// Notify (status channel) characteristic UUIDs. FF01 emits a handshake
    /// ("OK"); FF03 emits periodic status. The firmware won't honour print
    /// commands until it sees a subscriber here, so we still subscribe to both.
    public static let notifyCharacteristicUUIDStrings = ["FF01", "FF03"]

    /// New protocol (captured 2026-06-07 from the official Peripage iOS
    /// app via PacketLogger). The old `cmdReset = 10 11 FF FE 01` no
    /// longer triggers a print on the current firmware.
    public static let cmdStartA = Data([0x10, 0xff, 0x10, 0x00, 0x01])  // session init
    public static let cmdStartB = Data([0x10, 0xff, 0xfe, 0x01])         // ready / clear buffer
    public static let cmdEnd    = Data([0x10, 0xff, 0xfe, 0x45])         // commit and print
    public static let leadingSilenceBytes: Int = 1024
    public static let trailingFeedPx: UInt8 = 96

    /// Invert each byte (white pixel bit → 0, black pixel bit → 1) so the
    /// printer fires its heating elements correctly. Input is raw
    /// MSB-first 1bpp packed bytes from a 576px-wide bitmap.
    public static func encodeImageToBytes(_ rawBits: Data) -> Data {
        Data(rawBits.map { $0 ^ 0xFF })
    }

    /// Build the byte stream the new (post-2026-06 firmware) Peripage
    /// firmware accepts:
    ///   cmdStartA | cmdStartB | 1024×0x00 | GS v 0 raster (one block) | ESC J 96 | cmdEnd
    ///
    /// The `leadingFeed` / `trailingFeed` parameters are accepted for API
    /// compatibility but ignored — the new firmware uses a fixed leading
    /// silence and fixed 96-pixel trailing feed.
    public static func buildPayload(
        rasterBytes: Data,
        height: Int,
        leadingFeed: Int = 0,
        trailingFeed: Int = 0
    ) -> Data {
        precondition(rasterBytes.count == rowBytes * height,
                     "raster size (\(rasterBytes.count)) != rowBytes*height (\(rowBytes * height))")

        let xL = UInt8(rowBytes & 0xFF)
        let xH = UInt8((rowBytes >> 8) & 0xFF)
        let yL = UInt8(height & 0xFF)
        let yH = UInt8((height >> 8) & 0xFF)

        var out = Data()
        out.append(cmdStartA)
        out.append(cmdStartB)
        out.append(Data(repeating: 0x00, count: leadingSilenceBytes))
        out.append(contentsOf: [0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH])
        out.append(rasterBytes)
        out.append(contentsOf: [0x1B, 0x4A, trailingFeedPx])
        out.append(cmdEnd)
        return out
    }
}
