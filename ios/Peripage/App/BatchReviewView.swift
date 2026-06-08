import SwiftUI
import PhotosUI

struct BatchReviewView: View {
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    let items: [PhotosPickerItem]

    var body: some View {
        // Stub. Filled in by Task 3.
        VStack {
            Text("Review \(items.count) photos")
            Button("Cancel") { dismiss() }
        }
    }
}
