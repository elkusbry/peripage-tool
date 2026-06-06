import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public enum ImageProcessingError: Error, Equatable {
    case decodeFailed
    case unsupportedColorSpace
    case sizeMismatch(expected: Int, got: Int)
}

public enum ImageProcessor {

    // MARK: - Auto rotation

    /// Resolve `.auto` against the image's EXIF-corrected orientation.
    /// Landscape (or square) stays at `.deg0`; portrait becomes `.deg90`.
    public static func resolveRotation(_ rotation: Rotation, for imageData: Data) throws -> Rotation {
        if rotation != .auto { return rotation }
        let size = try orientedSize(of: imageData)
        return size.width >= size.height ? .deg0 : .deg90
    }

    /// Decode the image's pixel size *after* applying EXIF orientation.
    private static func orientedSize(of data: Data) throws -> CGSize {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ImageProcessingError.decodeFailed }

        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        // EXIF orientations 5–8 swap width and height.
        if (5...8).contains(orientation) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }
}
