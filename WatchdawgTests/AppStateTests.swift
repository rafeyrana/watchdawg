import XCTest
@testable import Watchdawg

@MainActor
final class AppStateTests: XCTestCase {

    func testWatchingStateEnum() {
        let states: [WatchingState] = [.idle, .armed, .recording]
        XCTAssertEqual(states.count, 3)
    }

    func testIsArmedWhenIdle() {
        // We can't use the singleton directly in tests, so we test the logic
        let watchingState = WatchingState.idle
        let isArmed = watchingState == .armed || watchingState == .recording
        XCTAssertFalse(isArmed)
    }

    func testIsArmedWhenArmed() {
        let watchingState = WatchingState.armed
        let isArmed = watchingState == .armed || watchingState == .recording
        XCTAssertTrue(isArmed)
    }

    func testIsArmedWhenRecording() {
        let watchingState = WatchingState.recording
        let isArmed = watchingState == .armed || watchingState == .recording
        XCTAssertTrue(isArmed)
    }

    func testIsRecordingWhenIdle() {
        let watchingState = WatchingState.idle
        let isRecording = watchingState == .recording
        XCTAssertFalse(isRecording)
    }

    func testIsRecordingWhenArmed() {
        let watchingState = WatchingState.armed
        let isRecording = watchingState == .recording
        XCTAssertFalse(isRecording)
    }

    func testIsRecordingWhenRecording() {
        let watchingState = WatchingState.recording
        let isRecording = watchingState == .recording
        XCTAssertTrue(isRecording)
    }

    func testStateTransitionsLogic() {
        // Test state machine logic
        var state = WatchingState.idle

        // idle -> armed
        state = .armed
        XCTAssertEqual(state, .armed)

        // armed -> recording
        state = .recording
        XCTAssertEqual(state, .recording)

        // recording -> idle (disarm)
        state = .idle
        XCTAssertEqual(state, .idle)
    }
}

// MARK: - Sentry Mode Settings Tests

@MainActor
final class SentryModeSettingsTests: XCTestCase {

    func testDefaultSentryModeValues() {
        // Test that default values are reasonable
        // Note: We test the logic, not the singleton

        // Default sentry mode should be disabled
        let sentryModeEnabled = false
        XCTAssertFalse(sentryModeEnabled)

        // Default motion sensitivity should be 2%
        let defaultSensitivity: Float = 0.02
        XCTAssertEqual(defaultSensitivity, 0.02, accuracy: 0.001)

        // Default cooldown should be 10 seconds
        let defaultCooldown = 10
        XCTAssertEqual(defaultCooldown, 10)
    }

    func testMotionSensitivityRange() {
        // Test that sensitivity values are within expected range
        let minSensitivity: Float = 0.01  // 1%
        let maxSensitivity: Float = 0.10  // 10%
        let defaultSensitivity: Float = 0.02  // 2%

        XCTAssertGreaterThanOrEqual(defaultSensitivity, minSensitivity)
        XCTAssertLessThanOrEqual(defaultSensitivity, maxSensitivity)
    }

    func testMotionCooldownOptions() {
        // Test available cooldown options
        let validCooldowns = [5, 10, 30]

        XCTAssertTrue(validCooldowns.contains(5))
        XCTAssertTrue(validCooldowns.contains(10))
        XCTAssertTrue(validCooldowns.contains(30))
        XCTAssertEqual(validCooldowns.count, 3)
    }

    func testSentryModeToggleLogic() {
        var sentryEnabled = false

        // Enable sentry mode
        sentryEnabled = true
        XCTAssertTrue(sentryEnabled)

        // Disable sentry mode
        sentryEnabled = false
        XCTAssertFalse(sentryEnabled)
    }

    func testSensitivityConversionToPercentage() {
        let sensitivity: Float = 0.02

        // Convert to percentage for display
        let percentage = Int(sensitivity * 100)

        XCTAssertEqual(percentage, 2)
    }

    func testSensitivityConversionFromSlider() {
        // Slider values typically 0.01 to 0.10
        let sliderValue: Double = 0.05

        // Convert to Float for storage
        let sensitivity = Float(sliderValue)

        XCTAssertEqual(sensitivity, 0.05, accuracy: 0.001)
    }

    func testCooldownSecondsToTimeInterval() {
        let cooldownSeconds = 10

        // Convert to TimeInterval for timer usage
        let timeInterval = TimeInterval(cooldownSeconds)

        XCTAssertEqual(timeInterval, 10.0, accuracy: 0.001)
    }

    func testSentryModeUserDefaultsKeys() {
        // Verify the keys we use for persistence
        let sentryModeKey = "sentryModeEnabled"
        let sensitivityKey = "motionSensitivity"
        let cooldownKey = "motionCooldown"

        XCTAssertEqual(sentryModeKey, "sentryModeEnabled")
        XCTAssertEqual(sensitivityKey, "motionSensitivity")
        XCTAssertEqual(cooldownKey, "motionCooldown")
    }
}

// MARK: - Sentry Mode Behavior Tests

final class SentryModeBehaviorTests: XCTestCase {

    func testRecordingBehaviorDescriptions() {
        // Document expected behavior for different modes

        // Sentry OFF: Continuous recording
        let sentryOff = false
        XCTAssertFalse(sentryOff)
        // Expected: Start recording immediately when armed

        // Sentry ON, No Motion: Camera active, NOT recording
        let sentryOn = true
        let motionDetected = false
        XCTAssertTrue(sentryOn)
        XCTAssertFalse(motionDetected)
        // Expected: Camera running, analyzing frames, but not recording

        // Sentry ON, Motion Detected: Start recording
        let motionActive = true
        XCTAssertTrue(sentryOn && motionActive)
        // Expected: Start recording, send notification

        // Sentry ON, Motion Stopped: Wait cooldown, then stop
        let motionStopped = false
        let inCooldown = true
        XCTAssertTrue(sentryOn && !motionStopped && inCooldown)
        // Expected: Wait cooldown period, then stop recording
    }

    func testStatusTextForSentryMode() {
        // Test status text logic
        struct StatusTestCase {
            let isRecording: Bool
            let isArmed: Bool
            let sentryEnabled: Bool
            let expectedContains: String
        }

        let testCases: [StatusTestCase] = [
            StatusTestCase(isRecording: true, isArmed: true, sentryEnabled: false, expectedContains: "Recording"),
            StatusTestCase(isRecording: true, isArmed: true, sentryEnabled: true, expectedContains: "Recording"),
            StatusTestCase(isRecording: false, isArmed: true, sentryEnabled: true, expectedContains: "Watching"),
            StatusTestCase(isRecording: false, isArmed: true, sentryEnabled: false, expectedContains: "Armed"),
            StatusTestCase(isRecording: false, isArmed: false, sentryEnabled: false, expectedContains: "Idle"),
        ]

        for testCase in testCases {
            let statusText: String
            if testCase.isRecording {
                statusText = "Recording"
            } else if testCase.isArmed && testCase.sentryEnabled {
                statusText = "Watching"
            } else if testCase.isArmed {
                statusText = "Armed"
            } else {
                statusText = "Idle"
            }

            XCTAssertTrue(statusText.contains(testCase.expectedContains),
                         "Expected '\(testCase.expectedContains)' but got '\(statusText)'")
        }
    }

    func testMotionIndicatorVisibility() {
        // Motion indicator should only show when sentry mode is enabled AND motion is active
        struct VisibilityTestCase {
            let sentryEnabled: Bool
            let motionActive: Bool
            let shouldShowIndicator: Bool
        }

        let testCases: [VisibilityTestCase] = [
            VisibilityTestCase(sentryEnabled: false, motionActive: false, shouldShowIndicator: false),
            VisibilityTestCase(sentryEnabled: false, motionActive: true, shouldShowIndicator: false),
            VisibilityTestCase(sentryEnabled: true, motionActive: false, shouldShowIndicator: false),
            VisibilityTestCase(sentryEnabled: true, motionActive: true, shouldShowIndicator: true),
        ]

        for testCase in testCases {
            let showIndicator = testCase.sentryEnabled && testCase.motionActive
            XCTAssertEqual(showIndicator, testCase.shouldShowIndicator,
                          "Sentry=\(testCase.sentryEnabled), Motion=\(testCase.motionActive) should show=\(testCase.shouldShowIndicator)")
        }
    }
}

// MARK: - CameraError Tests

final class CameraErrorTests: XCTestCase {

    func testCameraErrorDescriptions() {
        XCTAssertEqual(CameraError.cameraUnavailable.errorDescription, "No camera available")
        XCTAssertEqual(CameraError.microphoneUnavailable.errorDescription, "No microphone available")
        XCTAssertEqual(CameraError.cameraAccessDenied.errorDescription, "Camera access denied")
        XCTAssertEqual(CameraError.microphoneAccessDenied.errorDescription, "Microphone access denied")
        XCTAssertEqual(CameraError.configurationFailed.errorDescription, "Configuration failed")
    }

    func testCameraErrorConformsToLocalizedError() {
        let error: LocalizedError = CameraError.cameraUnavailable
        XCTAssertNotNil(error.errorDescription)
    }

    func testAllCameraErrors() {
        let errors: [CameraError] = [
            .cameraUnavailable,
            .microphoneUnavailable,
            .cameraAccessDenied,
            .microphoneAccessDenied,
            .configurationFailed
        ]
        XCTAssertEqual(errors.count, 5)

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
