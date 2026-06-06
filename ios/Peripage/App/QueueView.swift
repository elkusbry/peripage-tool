import SwiftUI

struct QueueView: View {
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(queue.jobs) { job in
                    row(for: job)
                    #if os(iOS)
                        .swipeActions {
                            if !job.status.isTerminal {
                                Button("Cancel", role: .destructive) { queue.cancel(job.id) }
                            }
                        }
                    #else
                        .contextMenu {
                            if !job.status.isTerminal {
                                Button("Cancel") { queue.cancel(job.id) }
                            }
                        }
                    #endif
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { pauseResumeButton }
                ToolbarItem(placement: .bottomBar) { Button("Clear completed") { queue.clearCompleted() } }
                #else
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem { pauseResumeButton }
                ToolbarItem { Button("Clear completed") { queue.clearCompleted() } }
                #endif
            }
            .navigationTitle("Queue")
        }
    }

    private var pauseResumeButton: some View {
        Button(queue.isPaused ? "Resume" : "Pause") {
            queue.isPaused ? queue.resume() : queue.pause()
        }
    }

    private func row(for job: PrintJob) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(jobTitle(job)).font(.headline)
                Text(statusLabel(job.status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .sending(let p) = job.status {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 80)
            }
        }
    }

    private func jobTitle(_ job: PrintJob) -> String {
        "Photo \(job.id.uuidString.prefix(6))"
    }

    private func statusLabel(_ status: JobStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .rendering: return "Rendering…"
        case .sending(let p): return "Sending \(Int(p * 100))%"
        case .done: return "Done"
        case .failed(let r): return "Failed — \(r)"
        }
    }
}
