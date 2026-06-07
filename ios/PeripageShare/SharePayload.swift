import Foundation
import UniformTypeIdentifiers

enum SharePayloadError: Error, LocalizedError {
    case noImageItem
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImageItem: return "The shared item isn't an image."
        case .loadFailed(let why): return "Couldn't load the shared image: \(why)"
        }
    }
}

enum SharePayload {
    /// Resolve the first image item in the input items into Data.
    /// Supports JPEG, PNG, HEIC (loaded as Data and decoded by ImageIO downstream).
    static func loadFirstImage(from inputItems: [Any]) async throws -> Data {
        let providers: [NSItemProvider] = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard let provider = providers.first else { throw SharePayloadError.noImageItem }

        // Try `public.image` raw data first (preserves original bytes for ImageIO).
        return try await withCheckedThrowingContinuation { cc in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data { cc.resume(returning: data); return }
                if let error { cc.resume(throwing: SharePayloadError.loadFailed(error.localizedDescription)); return }
                cc.resume(throwing: SharePayloadError.loadFailed("no data, no error"))
            }
        }
    }
}
