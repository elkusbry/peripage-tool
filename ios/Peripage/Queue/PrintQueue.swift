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

    public nonisolated init(printer: PrinterClientProtocol) {
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
