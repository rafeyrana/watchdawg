import XCTest
import CoreMedia
@testable import Watchdawg

// MARK: - MotionDetectorConfig Tests

final class MotionDetectorConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = MotionDetectorConfig.default

        XCTAssertEqual(config.pixelThreshold, 25)
        XCTAssertEqual(config.motionThreshold, 0.02, accuracy: 0.001)
        XCTAssertEqual(config.confirmationFrames, 3)
        XCTAssertEqual(config.cooldownSeconds, 10)
        XCTAssertEqual(config.analysisSize.width, 160)
        XCTAssertEqual(config.analysisSize.height, 120)
        XCTAssertEqual(config.analysisFrameRate, 5)
    }

    func testCustomConfig() {
        let config = MotionDetectorConfig(
            pixelThreshold: 50,
            motionThreshold: 0.05,
            confirmationFrames: 5,
            cooldownSeconds: 20,
            analysisSize: CGSize(width: 320, height: 240),
            analysisFrameRate: 10
        )

        XCTAssertEqual(config.pixelThreshold, 50)
        XCTAssertEqual(config.motionThreshold, 0.05, accuracy: 0.001)
        XCTAssertEqual(config.confirmationFrames, 5)
        XCTAssertEqual(config.cooldownSeconds, 20)
        XCTAssertEqual(config.analysisSize.width, 320)
        XCTAssertEqual(config.analysisSize.height, 240)
        XCTAssertEqual(config.analysisFrameRate, 10)
    }

    func testConfigWithHighSensitivity() {
        // High sensitivity = low threshold
        let config = MotionDetectorConfig(
            pixelThreshold: 10,
            motionThreshold: 0.01
        )

        XCTAssertEqual(config.pixelThreshold, 10)
        XCTAssertEqual(config.motionThreshold, 0.01, accuracy: 0.001)
    }

    func testConfigWithLowSensitivity() {
        // Low sensitivity = high threshold
        let config = MotionDetectorConfig(
            pixelThreshold: 100,
            motionThreshold: 0.10
        )

        XCTAssertEqual(config.pixelThreshold, 100)
        XCTAssertEqual(config.motionThreshold, 0.10, accuracy: 0.001)
    }
}

// MARK: - MotionState Tests

final class MotionStateTests: XCTestCase {

    func testMotionStateRawValues() {
        XCTAssertEqual(MotionState.idle.rawValue, "idle")
        XCTAssertEqual(MotionState.monitoring.rawValue, "monitoring")
        XCTAssertEqual(MotionState.confirming.rawValue, "confirming")
        XCTAssertEqual(MotionState.active.rawValue, "active")
        XCTAssertEqual(MotionState.cooldown.rawValue, "cooldown")
    }

    func testAllMotionStates() {
        let states: [MotionState] = [.idle, .monitoring, .confirming, .active, .cooldown]
        XCTAssertEqual(states.count, 5)
    }

    func testMotionStateEquality() {
        let state1 = MotionState.monitoring
        let state2 = MotionState.monitoring
        let state3 = MotionState.active

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }
}

// MARK: - MotionDetector Tests

@MainActor
final class MotionDetectorTests: XCTestCase {

    var detector: MotionDetector!
    var mockDelegate: MockMotionDetectorDelegate!

    override func setUp() async throws {
        detector = MotionDetector(config: .default)
        mockDelegate = MockMotionDetectorDelegate()
        detector.delegate = mockDelegate
    }

    override func tearDown() async throws {
        detector.stopMonitoring()
        detector = nil
        mockDelegate = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(detector.state, .idle)
        XCTAssertFalse(detector.isMotionDetected)
        XCTAssertEqual(detector.currentMotionLevel, 0.0)
    }

    func testStartMonitoring() {
        detector.startMonitoring()

        XCTAssertEqual(detector.state, .monitoring)
        XCTAssertFalse(detector.isMotionDetected)
    }

    func testStopMonitoring() {
        detector.startMonitoring()
        detector.stopMonitoring()

        XCTAssertEqual(detector.state, .idle)
        XCTAssertFalse(detector.isMotionDetected)
        XCTAssertEqual(detector.currentMotionLevel, 0.0)
    }

    func testStartMonitoringResetsState() {
        // First start and potentially get into active state
        detector.startMonitoring()

        // Stop and restart
        detector.stopMonitoring()
        detector.startMonitoring()

        XCTAssertEqual(detector.state, .monitoring)
        XCTAssertFalse(detector.isMotionDetected)
    }

    // MARK: - Config Update Tests

    func testUpdateMotionThreshold() {
        let originalThreshold = detector.config.motionThreshold

        detector.updateMotionThreshold(0.05)

        XCTAssertEqual(detector.config.motionThreshold, 0.05, accuracy: 0.001)
        XCTAssertNotEqual(detector.config.motionThreshold, originalThreshold)
    }

    func testUpdateCooldownSeconds() {
        let originalCooldown = detector.config.cooldownSeconds

        detector.updateCooldownSeconds(30)

        XCTAssertEqual(detector.config.cooldownSeconds, 30)
        XCTAssertNotEqual(detector.config.cooldownSeconds, originalCooldown)
    }

    func testUpdateFullConfig() {
        let newConfig = MotionDetectorConfig(
            pixelThreshold: 50,
            motionThreshold: 0.10,
            confirmationFrames: 5,
            cooldownSeconds: 20
        )

        detector.updateConfig(newConfig)

        XCTAssertEqual(detector.config.pixelThreshold, 50)
        XCTAssertEqual(detector.config.motionThreshold, 0.10, accuracy: 0.001)
        XCTAssertEqual(detector.config.confirmationFrames, 5)
        XCTAssertEqual(detector.config.cooldownSeconds, 20)
    }

    // MARK: - State Machine Logic Tests

    func testStateTransitionIdleToMonitoring() {
        XCTAssertEqual(detector.state, .idle)

        detector.startMonitoring()

        XCTAssertEqual(detector.state, .monitoring)
    }

    func testStateTransitionMonitoringToIdle() {
        detector.startMonitoring()
        XCTAssertEqual(detector.state, .monitoring)

        detector.stopMonitoring()

        XCTAssertEqual(detector.state, .idle)
    }

    // MARK: - Config Validation Tests

    func testConfigWithZeroConfirmationFrames() {
        let config = MotionDetectorConfig(confirmationFrames: 0)
        let testDetector = MotionDetector(config: config)

        XCTAssertEqual(testDetector.config.confirmationFrames, 0)
    }

    func testConfigWithZeroCooldown() {
        let config = MotionDetectorConfig(cooldownSeconds: 0)
        let testDetector = MotionDetector(config: config)

        XCTAssertEqual(testDetector.config.cooldownSeconds, 0)
    }

    func testConfigWithExtremeValues() {
        let config = MotionDetectorConfig(
            pixelThreshold: 255,
            motionThreshold: 1.0,
            confirmationFrames: 100,
            cooldownSeconds: 3600
        )
        let testDetector = MotionDetector(config: config)

        XCTAssertEqual(testDetector.config.pixelThreshold, 255)
        XCTAssertEqual(testDetector.config.motionThreshold, 1.0, accuracy: 0.001)
        XCTAssertEqual(testDetector.config.confirmationFrames, 100)
        XCTAssertEqual(testDetector.config.cooldownSeconds, 3600)
    }

    // MARK: - Published Properties Tests

    func testIsMotionDetectedInitiallyFalse() {
        XCTAssertFalse(detector.isMotionDetected)
    }

    func testCurrentMotionLevelInitiallyZero() {
        XCTAssertEqual(detector.currentMotionLevel, 0.0)
    }

    // MARK: - Delegate Tests

    func testDelegateIsSet() {
        XCTAssertNotNil(detector.delegate)
        XCTAssertTrue(detector.delegate === mockDelegate)
    }

    func testDelegateCanBeNil() {
        detector.delegate = nil
        XCTAssertNil(detector.delegate)
    }

    // MARK: - Multiple Start/Stop Cycles

    func testMultipleStartStopCycles() {
        for _ in 0..<5 {
            detector.startMonitoring()
            XCTAssertEqual(detector.state, .monitoring)

            detector.stopMonitoring()
            XCTAssertEqual(detector.state, .idle)
        }
    }

    func testDoubleStart() {
        detector.startMonitoring()
        detector.startMonitoring()

        XCTAssertEqual(detector.state, .monitoring)
    }

    func testDoubleStop() {
        detector.startMonitoring()
        detector.stopMonitoring()
        detector.stopMonitoring()

        XCTAssertEqual(detector.state, .idle)
    }

    func testStopWithoutStart() {
        detector.stopMonitoring()

        XCTAssertEqual(detector.state, .idle)
    }
}

// MARK: - Mock Delegate

final class MockMotionDetectorDelegate: MotionDetectorDelegate {
    var motionStartedCalled = false
    var motionEndedCalled = false
    var lastMotionStartTimestamp: CMTime?
    var lastMotionEndTimestamp: CMTime?
    var motionStartCount = 0
    var motionEndCount = 0

    func motionDetector(_ detector: MotionDetector, motionStarted timestamp: CMTime) {
        motionStartedCalled = true
        lastMotionStartTimestamp = timestamp
        motionStartCount += 1
    }

    func motionDetector(_ detector: MotionDetector, motionEnded timestamp: CMTime) {
        motionEndedCalled = true
        lastMotionEndTimestamp = timestamp
        motionEndCount += 1
    }

    func reset() {
        motionStartedCalled = false
        motionEndedCalled = false
        lastMotionStartTimestamp = nil
        lastMotionEndTimestamp = nil
        motionStartCount = 0
        motionEndCount = 0
    }
}

// MARK: - State Machine Detailed Tests

final class MotionStateMachineTests: XCTestCase {

    func testStateTransitionsDescription() {
        // Document expected state transitions:
        // IDLE -> MONITORING (startMonitoring)
        // MONITORING -> CONFIRMING (motion detected 1 frame)
        // CONFIRMING -> ACTIVE (motion confirmed N frames)
        // CONFIRMING -> MONITORING (false alarm, no motion)
        // ACTIVE -> COOLDOWN (no motion detected)
        // ACTIVE -> ACTIVE (motion continues)
        // COOLDOWN -> ACTIVE (motion resumes)
        // COOLDOWN -> MONITORING (cooldown expires)
        // Any state -> IDLE (stopMonitoring)

        let states: [MotionState] = [.idle, .monitoring, .confirming, .active, .cooldown]
        XCTAssertEqual(states.count, 5)
    }

    func testIdleStateDescription() {
        let state = MotionState.idle
        XCTAssertEqual(state.rawValue, "idle")
        // Idle: Not monitoring, no motion detection happening
    }

    func testMonitoringStateDescription() {
        let state = MotionState.monitoring
        XCTAssertEqual(state.rawValue, "monitoring")
        // Monitoring: Actively analyzing frames for motion
    }

    func testConfirmingStateDescription() {
        let state = MotionState.confirming
        XCTAssertEqual(state.rawValue, "confirming")
        // Confirming: Motion detected, waiting for confirmation frames
    }

    func testActiveStateDescription() {
        let state = MotionState.active
        XCTAssertEqual(state.rawValue, "active")
        // Active: Motion confirmed, recording should be happening
    }

    func testCooldownStateDescription() {
        let state = MotionState.cooldown
        XCTAssertEqual(state.rawValue, "cooldown")
        // Cooldown: No motion, waiting before stopping recording
    }
}

// MARK: - Config Edge Cases

final class MotionDetectorConfigEdgeCasesTests: XCTestCase {

    func testConfigWithMinimumValues() {
        let config = MotionDetectorConfig(
            pixelThreshold: 0,
            motionThreshold: 0.0,
            confirmationFrames: 0,
            cooldownSeconds: 0,
            analysisSize: CGSize(width: 1, height: 1),
            analysisFrameRate: 1
        )

        XCTAssertEqual(config.pixelThreshold, 0)
        XCTAssertEqual(config.motionThreshold, 0.0, accuracy: 0.001)
        XCTAssertEqual(config.confirmationFrames, 0)
        XCTAssertEqual(config.cooldownSeconds, 0)
        XCTAssertEqual(config.analysisSize.width, 1)
        XCTAssertEqual(config.analysisSize.height, 1)
        XCTAssertEqual(config.analysisFrameRate, 1)
    }

    func testConfigWithMaximumUInt8Threshold() {
        let config = MotionDetectorConfig(pixelThreshold: 255)
        XCTAssertEqual(config.pixelThreshold, 255)
    }

    func testConfigMotionThresholdBoundaries() {
        let lowConfig = MotionDetectorConfig(motionThreshold: 0.01)
        XCTAssertEqual(lowConfig.motionThreshold, 0.01, accuracy: 0.001)

        let highConfig = MotionDetectorConfig(motionThreshold: 0.10)
        XCTAssertEqual(highConfig.motionThreshold, 0.10, accuracy: 0.001)
    }

    func testDefaultConfigIsReasonable() {
        let config = MotionDetectorConfig.default

        // Pixel threshold should be reasonable (not too sensitive, not too insensitive)
        XCTAssertGreaterThan(config.pixelThreshold, 10)
        XCTAssertLessThan(config.pixelThreshold, 100)

        // Motion threshold should detect meaningful motion but not noise
        XCTAssertGreaterThan(config.motionThreshold, 0.005)
        XCTAssertLessThan(config.motionThreshold, 0.20)

        // Confirmation frames should be quick but not instant
        XCTAssertGreaterThanOrEqual(config.confirmationFrames, 2)
        XCTAssertLessThanOrEqual(config.confirmationFrames, 10)

        // Cooldown should be reasonable
        XCTAssertGreaterThanOrEqual(config.cooldownSeconds, 5)
        XCTAssertLessThanOrEqual(config.cooldownSeconds, 60)
    }
}
