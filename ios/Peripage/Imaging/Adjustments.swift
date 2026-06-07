import Foundation

public enum Rotation: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case deg0
    case deg90
    case deg180
    case deg270

    /// Title for the segmented picker.
    public var label: String {
        switch self {
        case .auto:   return "Auto"
        case .deg0:   return "0°"
        case .deg90:  return "90°"
        case .deg180: return "180°"
        case .deg270: return "270°"
        }
    }
}

public struct Adjustments: Equatable, Codable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var topMarginPx: Int
    public var bottomMarginPx: Int
    public var rotation: Rotation

    public init(
        brightness: Double = 1.0,
        contrast: Double = 1.2,
        topMarginPx: Int = 40,
        bottomMarginPx: Int = 40,
        rotation: Rotation = .auto
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.topMarginPx = topMarginPx
        self.bottomMarginPx = bottomMarginPx
        self.rotation = rotation
    }

    public static let `default` = Adjustments()
}
