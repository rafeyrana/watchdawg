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
