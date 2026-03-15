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
    @Published var notificationsEnabled: Bool = true
    @Published var notificationSoundEnabled: Bool = true

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
        NotificationManager.shared.sendArmedNotification()
    }

    func disarm() {
        watchingState = .idle
        currentRecordingURL = nil
        recordingStartTime = nil
        NotificationManager.shared.sendDisarmedNotification()
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

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
    }

    func setNotificationSoundEnabled(_ enabled: Bool) {
        notificationSoundEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationSoundEnabled")
    }

    private func loadSettings() {
        if let qualityString = UserDefaults.standard.string(forKey: "videoQuality"),
           let quality = VideoQuality(rawValue: qualityString) {
            currentQuality = quality
        }

        if UserDefaults.standard.object(forKey: "notificationsEnabled") != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        if UserDefaults.standard.object(forKey: "notificationSoundEnabled") != nil {
            notificationSoundEnabled = UserDefaults.standard.bool(forKey: "notificationSoundEnabled")
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(currentQuality.rawValue, forKey: "videoQuality")
    }
}
