import Foundation
import Combine

enum WatchingState {
    case idle
    case armed
    case recording
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var watchingState: WatchingState = .idle
    @Published var currentQuality: VideoQuality = .medium
    @Published var currentRecordingURL: URL?
    @Published var recordingStartTime: Date?

    var isArmed: Bool {
        watchingState == .armed || watchingState == .recording
    }

    var isRecording: Bool {
        watchingState == .recording
    }

    private init() {
        loadSettings()
    }

    func arm() {
        watchingState = .armed
    }

    func disarm() {
        watchingState = .idle
        currentRecordingURL = nil
        recordingStartTime = nil
    }

    func startRecording(url: URL) {
        watchingState = .recording
        currentRecordingURL = url
        recordingStartTime = Date()
    }

    func setQuality(_ quality: VideoQuality) {
        currentQuality = quality
        saveSettings()
    }

    private func loadSettings() {
        if let qualityString = UserDefaults.standard.string(forKey: "videoQuality"),
           let quality = VideoQuality(rawValue: qualityString) {
            currentQuality = quality
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(currentQuality.rawValue, forKey: "videoQuality")
    }
}
