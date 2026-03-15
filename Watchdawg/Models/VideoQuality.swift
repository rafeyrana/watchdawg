import AVFoundation

enum VideoQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var capturePreset: AVCaptureSession.Preset {
        switch self {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }

    var description: String {
        switch self {
        case .low:
            return "Low (~352x288)"
        case .medium:
            return "Medium (~480p)"
        case .high:
            return "High (~720p)"
        }
    }
}
