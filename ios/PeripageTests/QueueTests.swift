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
}
