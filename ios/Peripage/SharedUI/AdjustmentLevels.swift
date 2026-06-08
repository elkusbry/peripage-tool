import Foundation

// Three-tier discrete "feel" knobs that map onto the continuous Adjustments
// fields. Both PreviewView (host app) and ShareRootView (share extension)
// consume these so the UI vocabulary stays identical.

protocol AdjustmentOption: Hashable {
    var label: String { get }
    var icon: String { get }
}

enum BrightnessLevel: String, CaseIterable, AdjustmentOption {
    case dim, normal, bright

    var value: Double {
        switch self {
        case .dim:    return 0.8
        case .normal: return 1.0
        case .bright: return 1.4
        }
    }
    var label: String {
        switch self {
        case .dim:    return "Dim"
        case .normal: return "Normal"
        case .bright: return "Bright"
        }
    }
    var icon: String {
        switch self {
        case .dim:    return "sun.min"
        case .normal: return "sun.max"
        case .bright: return "sun.max.fill"
        }
    }
    static func from(_ v: Double) -> BrightnessLevel {
        BrightnessLevel.allCases.min(by: { abs($0.value - v) < abs($1.value - v) }) ?? .normal
    }
}

enum ContrastLevel: String, CaseIterable, AdjustmentOption {
    case soft, normal, bold

    var value: Double {
        switch self {
        case .soft:   return 0.9
        case .normal: return 1.2
        case .bold:   return 1.7
        }
    }
    var label: String {
        switch self {
        case .soft:   return "Soft"
        case .normal: return "Normal"
        case .bold:   return "Bold"
        }
    }
    var icon: String {
        switch self {
        case .soft:   return "circle.dotted"
        case .normal: return "circle.lefthalf.filled"
        case .bold:   return "circle.fill"
        }
    }
    static func from(_ v: Double) -> ContrastLevel {
        ContrastLevel.allCases.min(by: { abs($0.value - v) < abs($1.value - v) }) ?? .normal
    }
}

enum RotationOption: String, CaseIterable, AdjustmentOption {
    case auto, landscape, portrait

    var rotation: Rotation {
        switch self {
        case .auto:      return .auto
        case .landscape: return .deg0
        case .portrait:  return .deg90
        }
    }
    var label: String {
        switch self {
        case .auto:      return "Auto"
        case .landscape: return "Landscape"
        case .portrait:  return "Portrait"
        }
    }
    var icon: String {
        switch self {
        case .auto:      return "wand.and.stars"
        case .landscape: return "rectangle"
        case .portrait:  return "rectangle.portrait"
        }
    }
    static func from(_ r: Rotation) -> RotationOption {
        switch r {
        case .deg0:           return .landscape
        case .deg90:          return .portrait
        case .auto, .deg180, .deg270: return .auto
        }
    }
}
