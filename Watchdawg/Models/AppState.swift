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

    // Sentry Mode settings
    @Published var sentryModeEnabled: Bool = false
    @Published var motionSensitivity: Float = 0.02  // 2% default
    @Published var motionCooldown: Int = 10         // 10 seconds

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

    func setSentryModeEnabled(_ enabled: Bool) {
        sentryModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "sentryModeEnabled")
        // Sync with CameraManager
        CameraManager.shared.sentryModeEnabled = enabled
    }

    func setMotionSensitivity(_ sensitivity: Float) {
        motionSensitivity = sensitivity
        UserDefaults.standard.set(sensitivity, forKey: "motionSensitivity")
        // Update camera manager config
        CameraManager.shared.updateSentryConfig(motionThreshold: sensitivity)
    }

    func setMotionCooldown(_ cooldown: Int) {
        motionCooldown = cooldown
        UserDefaults.standard.set(cooldown, forKey: "motionCooldown")
        // Update camera manager config
        CameraManager.shared.updateSentryConfig(cooldownSeconds: cooldown)
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

        // Load Sentry Mode settings
        sentryModeEnabled = UserDefaults.standard.bool(forKey: "sentryModeEnabled")
        CameraManager.shared.sentryModeEnabled = sentryModeEnabled

        if UserDefaults.standard.object(forKey: "motionSensitivity") != nil {
            motionSensitivity = UserDefaults.standard.float(forKey: "motionSensitivity")
        }

        let savedCooldown = UserDefaults.standard.integer(forKey: "motionCooldown")
        motionCooldown = savedCooldown > 0 ? savedCooldown : 10
    }

    private func saveSettings() {
        UserDefaults.standard.set(currentQuality.rawValue, forKey: "videoQuality")
    }
}
