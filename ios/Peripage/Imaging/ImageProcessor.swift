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

    public struct ProcessedImage {
        public let previewCGImage: CGImage   // 8-bit grayscale post-dither, native size for preview
        public let rasterBytes: Data         // 1bpp MSB-first, white→bit 0 (printer-ready)
        public let width: Int                // == 576
        public let height: Int
    }

    public static func process(_ data: Data, adjustments: Adjustments) throws -> ProcessedImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ImageProcessingError.decodeFailed }

        // 1. EXIF-correct the raw bitmap
        let oriented = try orientedCopy(of: raw, sourceData: data)

        // 2. Resolve rotation (auto rule baked in here)
        let resolvedRotation: Rotation = adjustments.rotation == .auto
            ? (oriented.width >= oriented.height ? .deg0 : .deg90)
            : adjustments.rotation
        let rotated = rotate(oriented, by: resolvedRotation)

        // 3. Resize so width == 576, preserving aspect ratio
        let targetWidth = PeripageProtocol.printWidthPx
        let targetHeight = max(1, Int((Double(rotated.height) * Double(targetWidth) / Double(rotated.width)).rounded()))
        let resized = try resizeGrayscale(rotated, to: CGSize(width: targetWidth, height: targetHeight))

        // 4. Brightness + contrast in 8-bit grayscale space
        let adjusted = applyBrightnessContrast(resized, brightness: adjustments.brightness, contrast: adjustments.contrast)

        // 5. Floyd–Steinberg dither → 1bpp MSB-first packed bytes (uninverted)
        let rawBits = floydSteinbergDither(adjusted, width: targetWidth, height: targetHeight)
        let printerBytes = PeripageProtocol.encodeImageToBytes(rawBits)

        guard printerBytes.count == PeripageProtocol.rowBytes * targetHeight else {
            throw ImageProcessingError.sizeMismatch(
                expected: PeripageProtocol.rowBytes * targetHeight,
                got: printerBytes.count
            )
        }

        // Build an 8-bit grayscale preview from the same dither (for UI display)
        let previewCG = try grayscaleCGImage(fromBits: rawBits, width: targetWidth, height: targetHeight, invertForDisplay: true)

        return ProcessedImage(
            previewCGImage: previewCG,
            rasterBytes: printerBytes,
            width: targetWidth,
            height: targetHeight
        )
    }

    // MARK: - Pipeline helpers (CoreGraphics)

    private static func orientedCopy(of image: CGImage, sourceData: Data) throws -> CGImage {
        let src = CGImageSourceCreateWithData(sourceData as CFData, nil)
        let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation == 1 { return image }

        // Use CGContext to bake the orientation into pixel space.
        let isSwapped = (5...8).contains(orientation)
        let outW = isSwapped ? image.height : image.width
        let outH = isSwapped ? image.width  : image.height
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw ImageProcessingError.decodeFailed }

        applyOrientationTransform(ctx: ctx, orientation: orientation, width: outW, height: outH)
        ctx.draw(image, in: CGRect(x: 0, y: 0,
                                   width: isSwapped ? outH : outW,
                                   height: isSwapped ? outW : outH))
        guard let out = ctx.makeImage() else { throw ImageProcessingError.decodeFailed }
        return out
    }

    private static func applyOrientationTransform(ctx: CGContext, orientation: UInt32, width w: Int, height h: Int) {
        let W = CGFloat(w), H = CGFloat(h)
        switch orientation {
        case 2: ctx.translateBy(x: W, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 3: ctx.translateBy(x: W, y: H); ctx.rotate(by: .pi)
        case 4: ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        case 5: ctx.rotate(by: .pi/2); ctx.scaleBy(x: 1, y: -1)
        case 6: ctx.translateBy(x: W, y: 0); ctx.rotate(by: .pi/2)
        case 7: ctx.translateBy(x: W, y: H); ctx.rotate(by: .pi/2); ctx.scaleBy(x: 1, y: -1)
        case 8: ctx.translateBy(x: 0, y: H); ctx.rotate(by: -.pi/2)
        default: break
        }
    }

    private static func rotate(_ image: CGImage, by rotation: Rotation) -> CGImage {
        switch rotation {
        case .auto, .deg0: return image
        case .deg90:  return rotateCG(image, radians: -.pi / 2)   // clockwise
        case .deg180: return rotateCG(image, radians: .pi)
        case .deg270: return rotateCG(image, radians: .pi / 2)    // counter-clockwise
        }
    }

    private static func rotateCG(_ image: CGImage, radians: CGFloat) -> CGImage {
        let w = image.width, h = image.height
        let isQuarter = abs(radians.truncatingRemainder(dividingBy: .pi)) > 0.01
        let outW = isQuarter ? h : w
        let outH = isQuarter ? w : h
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        ctx.translateBy(x: CGFloat(outW)/2, y: CGFloat(outH)/2)
        ctx.rotate(by: radians)
        ctx.draw(image, in: CGRect(x: -CGFloat(w)/2, y: -CGFloat(h)/2, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage() ?? image
    }

    private static func resizeGrayscale(_ image: CGImage, to size: CGSize) throws -> CGImage {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw ImageProcessingError.decodeFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        guard let out = ctx.makeImage() else { throw ImageProcessingError.decodeFailed }
        return out
    }

    private static func applyBrightnessContrast(_ image: CGImage, brightness: Double, contrast: Double) -> CGImage {
        // Pull 8-bit grayscale pixels into a buffer, transform per byte, repack.
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // PIL semantics: brightness multiplies, contrast pivots around 128.
        for i in pixels.indices {
            var v = Double(pixels[i]) * brightness
            v = (v - 128) * contrast + 128
            pixels[i] = UInt8(max(0, min(255, v.rounded())))
        }

        guard let out = ctx.makeImage() else { return image }
        return out
    }

    /// Floyd–Steinberg dither over an 8-bit grayscale image; returns
    /// MSB-first 1bpp packed bytes where bit=1 means WHITE (uninverted).
    private static func floydSteinbergDither(_ image: CGImage, width w: Int, height h: Int) -> Data {
        var pixels = [Int](repeating: 0, count: w * h)
        var raw = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &raw, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in raw.indices { pixels[i] = Int(raw[i]) }

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let old = pixels[i]
                let new = old < 128 ? 0 : 255
                pixels[i] = new
                let err = old - new
                if x + 1 < w     { pixels[i + 1]      += err * 7 / 16 }
                if y + 1 < h {
                    if x > 0     { pixels[i + w - 1]  += err * 3 / 16 }
                                   pixels[i + w]      += err * 5 / 16
                    if x + 1 < w { pixels[i + w + 1]  += err * 1 / 16 }
                }
            }
        }

        // Pack MSB-first. Bit=1 means WHITE (255 in pixels).
        let rowBytes = PeripageProtocol.rowBytes
        var packed = Data(count: rowBytes * h)
        packed.withUnsafeMutableBytes { buf in
            for y in 0..<h {
                for x in 0..<w {
                    let p = pixels[y * w + x]
                    if p >= 128 {
                        let byteIndex = y * rowBytes + (x >> 3)
                        let bit: UInt8 = 0x80 >> UInt8(x & 7)
                        buf[byteIndex] |= bit
                    }
                }
            }
        }
        return packed
    }

    private static func grayscaleCGImage(fromBits bits: Data, width w: Int, height h: Int, invertForDisplay: Bool) throws -> CGImage {
        let rowBytes = PeripageProtocol.rowBytes
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let byte = bits[y * rowBytes + (x >> 3)]
                let bit = (byte >> UInt8(7 - (x & 7))) & 1
                let white = bit == 1
                pixels[y * w + x] = invertForDisplay ? (white ? 255 : 0) : (white ? 0 : 255)
            }
        }
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let img = ctx.makeImage() else {
            throw ImageProcessingError.decodeFailed
        }
        return img
    }
}
