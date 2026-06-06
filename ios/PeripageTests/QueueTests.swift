import Testing
import Foundation
@testable import Peripage

@Suite("PrintQueue")
struct QueueTests {

    private static func fixturesDir() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private func jobA() throws -> PrintJob {
        let data = try Data(contentsOf: Self.fixturesDir().appendingPathComponent("landscape_400x300.png"))
        return PrintJob(sourceData: data, adjustments: .default)
    }
    private func jobB() throws -> PrintJob {
        let data = try Data(contentsOf: Self.fixturesDir().appendingPathComponent("portrait_300x400.png"))
        return PrintJob(sourceData: data, adjustments: .default)
    }

    @Test("Queue drains jobs serially in FIFO order")
    func drainsSerially() async throws {
        let printer = MockPrinterClient()
        let queue = PrintQueue(printer: printer)
        let a = try jobA(); let b = try jobB()

        await queue.enqueue(a)
        await queue.enqueue(b)
        await queue.start()
        await queue.waitForIdle(timeout: .seconds(10))

        #expect(printer.sends.count == 2)
        #expect(printer.sends[0].jobId == a.id)
        #expect(printer.sends[1].jobId == b.id)
        let statuses = await queue.snapshot.map(\.status)
        #expect(statuses.allSatisfy { $0 == .done })
    }

    @Test("Pausing prevents further drain; resume continues")
    func pauseResume() async throws {
        let printer = MockPrinterClient()
        let queue = PrintQueue(printer: printer)
        let a = try jobA(); let b = try jobB()

        await queue.enqueue(a)
        await queue.enqueue(b)
        await queue.pause()
        await queue.start()
        await queue.waitForIdle(timeout: .milliseconds(200))

        // Paused: no sends yet
        #expect(printer.sends.isEmpty)

        await queue.resume()
        await queue.waitForIdle(timeout: .seconds(10))
        #expect(printer.sends.count == 2)
    }

    @Test("Two consecutive connect failures auto-pause the queue")
    func autoPauseAfterTwoFailures() async throws {
        let printer = MockPrinterClient()
        printer.nextFailures = [
            .connectThrows(.noPeripheralFound),
            .connectThrows(.noPeripheralFound),
        ]
        let queue = PrintQueue(printer: printer)
        await queue.enqueue(try jobA())
        await queue.enqueue(try jobB())
        await queue.start()
        await queue.waitForIdle(timeout: .seconds(5))

        let paused = await queue.isPaused
        #expect(paused == true)
        #expect(printer.sends.isEmpty)
        let firstFailed = await queue.snapshot.first.map { if case .failed = $0.status { return true } else { return false } }
        #expect(firstFailed == true)
    }
}
