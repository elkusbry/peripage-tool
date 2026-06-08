# Multi-Photo Print from iOS Home View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the iOS app's Home view pick multiple photos from the photo library, confirm them on a review grid (with × to drop any), and enqueue them all to print with default auto-layout.

**Architecture:** Swap `PhotosPicker`'s `selection` from single to array (max 20, ordered). When 1 photo is picked, keep today's `PreviewView` path. When 2+ are picked, present a new `BatchReviewView` sheet that loads each photo's bytes, shows a 3-column thumbnail grid with numbered badges and ×-to-remove, then enqueues remaining items as default `PrintJob`s in order. No queue, protocol, or share-extension changes.

**Tech Stack:** SwiftUI, PhotosUI (`PhotosPicker`, `PhotosPickerItem`), existing `PrintQueue` / `PrintJob` / `Adjustments` from this repo. xcodegen for project regen.

**Spec:** `docs/superpowers/specs/2026-06-07-multi-photo-print-design.md`

---

## File Structure

- Modify: `ios/Peripage/App/HomeView.swift` — switch the picker from single to multi-select; route 1-photo to existing `PreviewView`, 2+ to new `BatchReviewView` sheet; clear state on dismiss.
- Create: `ios/Peripage/App/BatchReviewView.swift` — new SwiftUI view holding the review grid, loading logic, ×-remove, and "Print all" action. Lives alongside the other Home-view UI files in `App/`.
- Touch (regenerate): `ios/Peripage.xcodeproj/` via `xcodegen generate`. The new file is auto-picked up because the Peripage target sources from the whole `Peripage/` folder; we just need the project file to reflect it.

No other files change. The Share Extension, CLI, web UI, fixtures, protocol files, and Swift Testing parity suite are untouched.

---

## Task 1: Stub `BatchReviewView` so the project compiles after Task 2's HomeView change

We need the new view to exist (even as a placeholder) before HomeView starts referencing it. This task creates the minimal file; Task 3 fleshes it out.

**Files:**
- Create: `ios/Peripage/App/BatchReviewView.swift`

- [ ] **Step 1: Create the stub file**

```swift
// ios/Peripage/App/BatchReviewView.swift
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
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `cd ios && xcodegen generate && cd ..`
Expected: "Loaded project … Created project at Peripage.xcodeproj" with no errors.

- [ ] **Step 3: Build to confirm the new file compiles**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20 && cd ..`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/App/BatchReviewView.swift
git commit -m "ios: add BatchReviewView stub for multi-photo flow"
```

---

## Task 2: Switch HomeView to multi-select and route by count

Wire the picker to an array, gate the existing `PreviewView` path on `count == 1`, and present `BatchReviewView` on `count >= 2`. Reset state when either sheet/destination closes so the picker can fire again.

**Files:**
- Modify: `ios/Peripage/App/HomeView.swift` (full body — easier to read as a diff than line ranges; the file is ~90 lines)

- [ ] **Step 1: Replace the `HomeView` struct body**

Replace the existing `HomeView` struct (lines 4–63 of `ios/Peripage/App/HomeView.swift`) with this. `LogTail` and the imports below stay as-is.

```swift
struct HomeView: View {
    @Environment(PrinterClient.self) private var printer
    @Environment(PrintQueue.self) private var queue

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickedData: Data?            // populated only for the 1-photo path
    @State private var showBatchReview = false      // true when 2+ photos were picked
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var showDebug = false
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 24) {
            StatusPill(
                state: printer.state,
                queueCount: queue.jobs.filter { !$0.status.isTerminal }.count,
                onLongPress: { showDebug = true }
            )
            .padding(.top)

            Spacer()

            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 20,
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
                    .font(.title2.bold())
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(Capsule().fill(.tint))
                    .foregroundStyle(.white)
            }

            if queue.jobs.contains(where: { !$0.status.isTerminal }) {
                Button {
                    showQueue = true
                } label: {
                    Label("Queue (\(queue.jobs.filter { !$0.status.isTerminal }.count))",
                          systemImage: "list.bullet")
                }
            }

            Spacer()

            LogTail()
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .padding()
        .navigationDestination(isPresented: Binding(
            get: { pickedData != nil },
            set: { if !$0 { pickedData = nil; photoItems = [] } }
        )) {
            if let data = pickedData {
                PreviewView(sourceData: data)
            }
        }
        .sheet(isPresented: $showBatchReview, onDismiss: {
            batchItems = []
            photoItems = []
        }) {
            BatchReviewView(items: batchItems)
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showDebug) { DebugLogView() }
        .task(id: photoItems) {
            // Route by selection count. Empty = no-op (picker cancelled or state reset).
            switch photoItems.count {
            case 0:
                return
            case 1:
                pickedData = try? await photoItems[0].loadTransferable(type: Data.self)
            default:
                batchItems = photoItems
                showBatchReview = true
            }
        }
    }
}
```

- [ ] **Step 2: Build for iOS**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20 && cd ..`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build for macOS (the app is multi-platform)**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'generic/platform=macOS' -quiet build 2>&1 | tail -20 && cd ..`
Expected: `** BUILD SUCCEEDED **`. If macOS complains about `selectionBehavior: .ordered` or `maxSelectionCount:`, both are available on macOS 13+/iOS 16+ — the deployment target should already cover that. If not, the failure is a real signal to surface, not to paper over.

- [ ] **Step 4: Commit**

```bash
git add ios/Peripage/App/HomeView.swift
git commit -m "ios: multi-select PhotosPicker on Home view, route by count"
```

---

## Task 3: Flesh out `BatchReviewView` — load, grid, ×-remove, Print all

Replace the stub with the real view. This is the bulk of the feature.

**Files:**
- Modify: `ios/Peripage/App/BatchReviewView.swift` (replace entire contents)

- [ ] **Step 1: Replace the file with the full implementation**

```swift
// ios/Peripage/App/BatchReviewView.swift
import SwiftUI
import PhotosUI
import UIKit

struct BatchReviewView: View {
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    let items: [PhotosPickerItem]

    @State private var entries: [BatchEntry] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        tile(index: index, entry: entry)
                    }
                }
                .padding()
            }
            .navigationTitle("Review \(entries.count) Photo\(entries.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                printAllBar
            }
        }
        .task {
            await loadAll()
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(index: Int, entry: BatchEntry) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch entry.state {
                case .loading:
                    placeholder { ProgressView() }
                case .ready(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .failed:
                    placeholder {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Numbered badge — reflects current index after any removals.
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(6)

            // × in top-trailing.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        remove(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.secondary.opacity(0.15)
            content()
        }
    }

    // MARK: - Bottom bar

    private var printAllBar: some View {
        let readyCount = entries.filter { if case .ready = $0.state { return true } else { return false } }.count
        let anyLoading = entries.contains { if case .loading = $0.state { return true } else { return false } }
        let label = readyCount == 0 ? "Print all" : "Print all \(readyCount)"

        return Button {
            printAll()
        } label: {
            Text(label)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(.tint))
                .foregroundStyle(.white)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .disabled(anyLoading || readyCount == 0)
    }

    // MARK: - Actions

    private func loadAll() async {
        // Seed entries up front so the grid renders placeholders immediately.
        if entries.isEmpty {
            entries = items.map { BatchEntry(pickerItem: $0) }
        }

        await withTaskGroup(of: (UUID, BatchEntry.State).self) { group in
            for entry in entries {
                group.addTask {
                    do {
                        guard let data = try await entry.pickerItem.loadTransferable(type: Data.self) else {
                            return (entry.id, .failed)
                        }
                        guard let image = downscaled(data: data) else {
                            return (entry.id, .failed)
                        }
                        return (entry.id, .ready(thumb: image, data: data))
                    } catch {
                        return (entry.id, .failed)
                    }
                }
            }
            for await (id, state) in group {
                if let i = entries.firstIndex(where: { $0.id == id }) {
                    entries[i].state = state
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func printAll() {
        for entry in entries {
            if case .ready(_, let data) = entry.state {
                queue.enqueue(PrintJob(sourceData: data, adjustments: .default))
            }
        }
        dismiss()
    }
}

// MARK: - Model

private struct BatchEntry: Identifiable, Equatable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    var state: State = .loading

    enum State: Equatable {
        case loading
        case ready(thumb: UIImage, data: Data)
        case failed
    }

    static func == (lhs: BatchEntry, rhs: BatchEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helpers

/// Decode `data` and downscale to ~600pt on the long edge for grid display.
/// Returns nil if the data isn't a decodable image.
private func downscaled(data: Data) -> UIImage? {
    guard let source = UIImage(data: data) else { return nil }
    let maxEdge: CGFloat = 600
    let w = source.size.width
    let h = source.size.height
    guard max(w, h) > maxEdge else { return source }
    let scale = maxEdge / max(w, h)
    let target = CGSize(width: w * scale, height: h * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: target, format: format)
    return renderer.image { _ in
        source.draw(in: CGRect(origin: .zero, size: target))
    }
}
```

- [ ] **Step 2: Build for iOS**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20 && cd ..`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build for macOS**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'generic/platform=macOS' -quiet build 2>&1 | tail -20 && cd ..`
Expected: `** BUILD SUCCEEDED **`. If `import UIKit` fails on macOS, the file needs a small `#if os(iOS)` wrap around the body — see the contingency note below. (Most likely the existing Catalyst/iOS-on-Mac config already makes UIKit available; the build will tell you.)

If macOS fails on `import UIKit`, wrap the file's contents in `#if canImport(UIKit)` … `#endif` and add an `#else` branch that prints a single `Text("Multi-photo selection is iOS-only")`. Don't silently disable; surface it.

- [ ] **Step 4: Run the existing Swift Testing suite to confirm nothing else broke**

Run: `cd ios && xcodebuild -project Peripage.xcodeproj -scheme Peripage -destination 'platform=iOS Simulator,name=iPhone 15' test 2>&1 | tail -30 && cd ..`
Expected: parity tests pass (this feature touches no protocol code, so they should be unaffected).

- [ ] **Step 5: Commit**

```bash
git add ios/Peripage/App/BatchReviewView.swift
git commit -m "ios: BatchReviewView — load, grid, ×-remove, Print all"
```

---

## Task 4: Manual on-device verification

The feature is pure UI on top of an unchanged queue — no automated test covers the picker, grid, or enqueue path end-to-end. Verify on real hardware.

**Files:** none.

- [ ] **Step 1: Install on iPhone**

Run from Xcode: select the Peripage scheme, "My iPhone" destination, ⌘R. Confirm app launches and connects to the printer.

- [ ] **Step 2: Single-photo regression**

Tap "Choose Photos" → pick exactly 1 photo → confirm `PreviewView` opens (the existing per-photo tuning UI). Print it. Expected: prints as before. This proves Task 2's routing didn't break the 1-photo path.

- [ ] **Step 3: Multi-photo happy path**

Tap "Choose Photos" → pick 3 photos in a deliberate order (note the numbered badges in the picker) → confirm `BatchReviewView` opens with all 3 thumbnails and matching badge numbers. Tap "Print all 3". Expected: sheet dismisses, queue view shows 3 jobs progressing one at a time, all 3 prints come out in the picked order.

- [ ] **Step 4: × removal**

Tap "Choose Photos" → pick 3 photos → tap × on the middle one → confirm grid now shows 2 tiles with renumbered badges (1 and 2). Tap "Print all 2". Expected: only the first and third selected photos print, in that order.

- [ ] **Step 5: Cancel**

Pick 2 photos → on the review grid, tap Cancel. Expected: sheet dismisses, queue is unchanged (no new jobs), tapping "Choose Photos" again works normally (state was reset).

- [ ] **Step 6: Stress check**

Pick the maximum of 20 photos. Expected: grid renders smoothly (≈3-second load is acceptable; nothing should hang), "Print all 20" enqueues all 20, queue drains.

- [ ] **Step 7: Update STATUS.md if anything surprising surfaced**

If verification turned up a quirk worth recording (memory headroom on 20 large RAWs, unexpected ordering behavior from Photos.app, etc.), add a one-line note under "Outstanding ideas / nice-to-haves" in `STATUS.md`. Otherwise skip.

- [ ] **Step 8: Final commit**

If any code or STATUS.md changes were needed during verification:

```bash
git add -A
git commit -m "ios: multi-photo verification fixes"
```

Otherwise nothing to commit — verification done.

---

## Done criteria

- Picking 1 photo still opens `PreviewView`.
- Picking 2–20 photos opens `BatchReviewView`, which shows numbered thumbnails, supports ×-removal, and enqueues remaining items as default `PrintJob`s in order.
- All builds succeed on iOS and macOS destinations.
- Existing Swift Testing parity suite still passes.
- Manual verification on real hardware confirms prints come out in the expected order.
