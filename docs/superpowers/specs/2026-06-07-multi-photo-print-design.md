# Multi-Photo Print from iOS Home View — Design

> 2026-06-07. Scope: iOS app Home view only. CLI, Web UI, Share
> Extension, and macOS app are unchanged.

## Why

Today the Home view's `PhotosPicker` accepts one photo at a time. Picking
five photos to print is five separate pick → preview → print cycles.
This adds a batch path so the user can pick N photos, confirm they're
the right ones, and enqueue them all in order.

## What changes

### 1. Picker (`HomeView.swift`)

- `@State private var photoItem: PhotosPickerItem?`
  becomes
  `@State private var photoItems: [PhotosPickerItem] = []`
- `PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared())`
  becomes
  `PhotosPicker(selection: $photoItems, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images, photoLibrary: .shared())`
- `maxSelectionCount: 20` — guard against accidentally selecting a
  whole album. The queue can handle more, but loading 100 originals
  into memory for the review grid would be painful. 20 is generous
  for the use case.
- `.ordered` — Photos.app shows numbered selection badges and returns
  items in tap order, which is the order they'll print.

### 2. Routing

In `HomeView`'s `.onChange(of: photoItems)`:

- **0 items**: do nothing.
- **1 item**: load its data and present `PreviewView` (unchanged
  behavior — preserves per-photo adjustments for the single-photo case).
- **2+ items**: present a new `BatchReviewView` sheet, passing the
  array of `PhotosPickerItem`s.

After either sheet dismisses, reset `photoItems = []`.

### 3. New file: `BatchReviewView.swift`

Lives in `ios/Peripage/App/`. Plain SwiftUI view, no shared dependencies
beyond `PrintQueue` and `PrintJob` (which the Share Extension target
already shares — no `Project.yml` changes needed).

**Inputs**: `[PhotosPickerItem]` passed in.

**State**:
- `@State items: [BatchEntry]` — local mutable list so × can remove.
  Each `BatchEntry` holds the `PhotosPickerItem`, an optional
  `UIImage` thumbnail (nil until loaded), and the raw `Data` (nil
  until loaded; needed for the actual print job).

**Loading**:
- `.task` on appear: for each entry concurrently, call
  `item.loadTransferable(type: Data.self)`. Store the raw data.
  Decode a thumbnail from it via `UIImage(data:)` then downscale
  (target ~300pt on the long edge) so the grid stays smooth.
- While loading: show a placeholder tile (gray rect with a small
  progress spinner).

**Layout**:
- `LazyVGrid` with 3 fixed columns, square aspect-ratio thumbnails.
- Each tile:
  - Image, `aspectRatio(contentMode: .fill)`, clipped.
  - Numbered badge in top-leading (1, 2, 3, …), reflecting current
    order in `items`.
  - `×` button in top-trailing that removes the entry. Removal
    renumbers the rest.
- Title bar: "Review N photos" (count updates as entries are removed).
- Bottom bar (sticky):
  - "Cancel" — dismisses, queues nothing.
  - "Print all N" — calls `queue.enqueue(PrintJob(sourceData: data, adjustments: Adjustments()))`
    for each entry whose data is loaded, in order, then dismisses.
    Disabled while any entry is still loading or when the list is empty.

**Adjustments**: every batch job uses the default `Adjustments()` —
auto-rotate, default brightness/contrast/dither. This matches the
Share Extension's existing behavior. The user has confirmed they
only use auto-layout; per-photo tuning stays in `PreviewView` for
single-photo prints.

### 4. What does NOT change

- `PrintQueue` API. The queue already serializes jobs and we just
  enqueue N of them.
- `PrintJob` shape.
- The Peripage protocol or any of the three protocol sites.
- Parity fixtures or `ProtocolParityTests`.
- The Share Extension. (It already does `attachments.first` — N-photo
  share-sheet support is a separate, larger piece of work and is out
  of scope here.)
- `Project.yml` / `xcodegen` config. Only existing source files are
  touched plus one new file in an already-included folder.

## UX flow

1. Home view → tap "Pick photos".
2. iOS PhotosPicker opens; user taps photos in desired print order
   (badges 1–N appear).
3. Picker dismisses with N items.
4. If N == 1: existing `PreviewView` opens. (Unchanged.)
5. If N ≥ 2: `BatchReviewView` sheet opens with the grid. User can
   tap × on any tile to drop it. User taps "Print all M".
6. Each remaining photo is enqueued as its own job. The Queue view
   shows them progressing one at a time.

## Failure modes

- **Picker dismissed with no selection**: `onChange` fires with empty
  array; no-op.
- **`loadTransferable` fails for one entry**: tile shows a small error
  state in place of the thumbnail; "Print all" treats that entry as
  not-loaded (skipped from the enqueue, with a one-line note "1 photo
  couldn't be loaded" shown briefly). Other entries still print.
- **All `loadTransferable`s fail**: "Print all" stays disabled; user
  hits Cancel.
- **Printer offline / BLE drops mid-batch**: existing queue behavior
  applies — jobs go to "error" state in the Queue view, user can
  retry from there. No new error handling needed.

## Manual verification

- Pick 3 photos in a specific order, hit Print all, confirm prints
  come out in that order.
- Pick 3 photos, remove the middle one with ×, confirm only 2 prints
  come out and they are the first and third selected.
- Pick 1 photo, confirm `PreviewView` opens (no behavior change).
- Pick 20 photos, confirm the grid renders smoothly and all 20 print.
- Cancel from `BatchReviewView` and confirm nothing was queued.

## Out of scope

- N-photo handling in the iOS Share Extension.
- Multi-file selection in the Web UI.
- CLI batch mode (the CLI already takes a path argument; batch is a
  shell loop and doesn't need product work).
- Per-photo adjustments inside the batch flow.
- Reordering in `BatchReviewView` (selection-order from the picker
  is the order — no drag-to-reorder).
