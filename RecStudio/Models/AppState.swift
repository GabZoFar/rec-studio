import SwiftUI
import ScreenCaptureKit

enum RecordingPhase: Equatable {
    case setup
    case countdown(Int)
    case recording
    case processing
    case editing
}

enum BackgroundPreset: String, CaseIterable, Identifiable {
    case midnight = "Midnight"
    case ocean = "Ocean"
    case sunset = "Sunset"
    case forest = "Forest"
    case lavender = "Lavender"
    case slate = "Slate"

    var id: String { rawValue }

    var colors: (start: Color, end: Color) {
        switch self {
        case .midnight: return (Color(hex: "0f0c29"), Color(hex: "302b63"))
        case .ocean:    return (Color(hex: "1a2980"), Color(hex: "26d0ce"))
        case .sunset:   return (Color(hex: "e65c00"), Color(hex: "f9d423"))
        case .forest:   return (Color(hex: "0b8793"), Color(hex: "360033"))
        case .lavender: return (Color(hex: "8e2de2"), Color(hex: "4a00e0"))
        case .slate:    return (Color(hex: "2c3e50"), Color(hex: "3498db"))
        }
    }

    var cgColors: (start: CGColor, end: CGColor) {
        (NSColor(colors.start).cgColor, NSColor(colors.end).cgColor)
    }
}

struct ExportSettings {
    var width: Int = 1920
    var height: Int = 1080
    var frameRate: Int = 60
    var bitRate: Int = 20_000_000
    var background: BackgroundPreset = .midnight
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 48
    var shadowRadius: CGFloat = 24
    var enableZoom: Bool = true
    var maxZoom: CGFloat = 2.0
}

final class AppState: ObservableObject {
    @Published var phase: RecordingPhase = .setup
    @Published var selectedDisplay: SCDisplay?
    @Published var rawVideoURL: URL?
    @Published var exportedVideoURL: URL?
    @Published var exportProgress: Double = 0
    @Published var errorMessage: String?
    @Published var exportSettings = ExportSettings()

    let screenRecorder = ScreenRecorder()
}

// MARK: - Color Utilities

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    static let appBackground = Color(hex: "0f0f17")
    static let appSurface = Color(hex: "1a1a2e")
    static let appSurfaceHover = Color(hex: "252545")
    static let appBorder = Color(hex: "2a2a4a")
    static let appAccent = Color(hex: "6c5ce7")
    static let appRed = Color(hex: "ff4757")
    static let appGreen = Color(hex: "2ed573")
    static let appTextPrimary = Color(hex: "f0f0f0")
    static let appTextSecondary = Color(hex: "8888aa")
}
