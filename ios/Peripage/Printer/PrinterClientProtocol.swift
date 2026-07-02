import Foundation

public protocol PrinterClientProtocol: AnyObject, Sendable {
    /// Observable current state.
    var state: PrinterState { get }

    /// Ensure we're connected to a Peripage. Scans if no peripheral is
    /// already in hand. Throws `BLEError` on permission / scan-timeout
    /// failure.
    func ensureConnected() async throws

    /// Send a single payload to the printer in MTU-sized chunks, deadline-paced
    /// at `PeripageProtocol.targetBytesPerSecond`. Updates `state` to
    /// `.sending(jobId, progress)`. `height` is the raster row count, used to
    /// size the post-send drain wait. Throws on disconnect / write failure.
    func send(_ payload: Data, jobId: UUID, height: Int) async throws

    /// Cleanly disconnect (called at queue idle).
    func disconnect() async
}
