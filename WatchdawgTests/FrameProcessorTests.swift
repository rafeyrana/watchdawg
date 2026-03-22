import XCTest
import CoreVideo
@testable import Watchdawg

final class FrameProcessorTests: XCTestCase {

    // MARK: - Absolute Difference Tests

    func testAbsoluteDifferenceIdenticalBuffers() {
        let buffer1: [UInt8] = [100, 100, 100, 100]
        let buffer2: [UInt8] = [100, 100, 100, 100]

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, [0, 0, 0, 0])
    }

    func testAbsoluteDifferenceCompletelyDifferent() {
        let buffer1: [UInt8] = [0, 0, 0, 0]
        let buffer2: [UInt8] = [255, 255, 255, 255]

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, [255, 255, 255, 255])
    }

    func testAbsoluteDifferencePartialChange() {
        let buffer1: [UInt8] = [100, 150, 200, 50]
        let buffer2: [UInt8] = [100, 100, 100, 100]

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, [0, 50, 100, 50])
    }

    func testAbsoluteDifferenceReversed() {
        // Test that |a - b| == |b - a|
        let buffer1: [UInt8] = [50, 100, 150, 200]
        let buffer2: [UInt8] = [100, 150, 200, 250]

        let result1 = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)
        let result2 = FrameProcessor.absoluteDifference(current: buffer2, previous: buffer1)

        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)
        XCTAssertEqual(result1, result2)
        XCTAssertEqual(result1, [50, 50, 50, 50])
    }

    func testAbsoluteDifferenceMismatchedSizes() {
        let buffer1: [UInt8] = [100, 100]
        let buffer2: [UInt8] = [100, 100, 100]

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNil(result)
    }

    func testAbsoluteDifferenceEmptyBuffers() {
        let buffer1: [UInt8] = []
        let buffer2: [UInt8] = []

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, [])
    }

    func testAbsoluteDifferenceLargeBuffer() {
        // Test with a buffer size similar to 160x120 analysis frame
        let size = 160 * 120
        var buffer1 = [UInt8](repeating: 100, count: size)
        var buffer2 = [UInt8](repeating: 100, count: size)

        // Change 10% of pixels
        let changedPixels = size / 10
        for i in 0..<changedPixels {
            buffer1[i] = 200
        }

        let result = FrameProcessor.absoluteDifference(current: buffer1, previous: buffer2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, size)

        // First changedPixels should have diff of 100
        for i in 0..<changedPixels {
            XCTAssertEqual(result?[i], 100)
        }
        // Rest should be 0
        for i in changedPixels..<size {
            XCTAssertEqual(result?[i], 0)
        }
    }

    // MARK: - Motion Percentage Tests

    func testMotionPercentageNoMotion() {
        let diffBuffer: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 0.0)
    }

    func testMotionPercentageAllMotion() {
        let diffBuffer: [UInt8] = [100, 100, 100, 100, 100, 100, 100, 100, 100, 100]

        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 1.0)
    }

    func testMotionPercentageHalfMotion() {
        let diffBuffer: [UInt8] = [100, 100, 100, 100, 100, 0, 0, 0, 0, 0]

        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 0.5, accuracy: 0.001)
    }

    func testMotionPercentageThresholdBoundary() {
        // Values exactly at threshold should NOT count as motion (must be > threshold)
        let diffBuffer: [UInt8] = [25, 25, 25, 25, 26, 26, 26, 26, 26, 26]

        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)

        // 6 pixels above 25, 4 at exactly 25
        XCTAssertEqual(percentage, 0.6, accuracy: 0.001)
    }

    func testMotionPercentageEmptyBuffer() {
        let diffBuffer: [UInt8] = []

        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 0.0)
    }

    func testMotionPercentageHighThreshold() {
        let diffBuffer: [UInt8] = [50, 100, 150, 200, 250]

        // With threshold of 200, only values > 200 count
        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 200)

        // Only 250 is > 200
        XCTAssertEqual(percentage, 0.2, accuracy: 0.001)
    }

    func testMotionPercentageZeroThreshold() {
        let diffBuffer: [UInt8] = [0, 1, 2, 3, 4]

        // With threshold of 0, all values > 0 count
        let percentage = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 0)

        // 4 values are > 0
        XCTAssertEqual(percentage, 0.8, accuracy: 0.001)
    }

    // MARK: - Optimized Motion Percentage Tests

    func testMotionPercentageOptimizedMatchesRegular() {
        let diffBuffer: [UInt8] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]

        let regular = FrameProcessor.motionPercentage(diffBuffer: diffBuffer, threshold: 25)
        let optimized = FrameProcessor.motionPercentageOptimized(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(regular, optimized, accuracy: 0.001)
    }

    func testMotionPercentageOptimizedEmptyBuffer() {
        let diffBuffer: [UInt8] = []

        let percentage = FrameProcessor.motionPercentageOptimized(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 0.0)
    }

    func testMotionPercentageOptimizedLargeBuffer() {
        // Test with realistic frame size
        let size = 160 * 120
        var diffBuffer = [UInt8](repeating: 0, count: size)

        // Set 2% of pixels to have motion (above threshold)
        let motionPixels = Int(Float(size) * 0.02)
        for i in 0..<motionPixels {
            diffBuffer[i] = 50
        }

        let percentage = FrameProcessor.motionPercentageOptimized(diffBuffer: diffBuffer, threshold: 25)

        XCTAssertEqual(percentage, 0.02, accuracy: 0.001)
    }

    // MARK: - Analysis Size Tests

    func testAnalysisSizeConstants() {
        XCTAssertEqual(FrameProcessor.analysisSize.width, 160)
        XCTAssertEqual(FrameProcessor.analysisSize.height, 120)
    }

    // MARK: - Integration Tests

    func testMotionDetectionWorkflow() {
        // Simulate a complete motion detection workflow
        let size = 100

        // Frame 1: baseline
        let frame1 = [UInt8](repeating: 100, count: size)

        // Frame 2: 5% of pixels changed significantly
        var frame2 = [UInt8](repeating: 100, count: size)
        for i in 0..<5 {
            frame2[i] = 200  // 100 difference
        }

        // Calculate difference
        guard let diff = FrameProcessor.absoluteDifference(current: frame2, previous: frame1) else {
            XCTFail("absoluteDifference returned nil")
            return
        }

        // Calculate motion percentage
        let motionLevel = FrameProcessor.motionPercentage(diffBuffer: diff, threshold: 25)

        // Should detect 5% motion
        XCTAssertEqual(motionLevel, 0.05, accuracy: 0.001)

        // With 2% threshold, this should trigger motion
        let motionThreshold: Float = 0.02
        XCTAssertTrue(motionLevel >= motionThreshold)
    }

    func testNoMotionWorkflow() {
        let size = 100

        // Two identical frames
        let frame1 = [UInt8](repeating: 128, count: size)
        let frame2 = [UInt8](repeating: 128, count: size)

        guard let diff = FrameProcessor.absoluteDifference(current: frame2, previous: frame1) else {
            XCTFail("absoluteDifference returned nil")
            return
        }

        let motionLevel = FrameProcessor.motionPercentage(diffBuffer: diff, threshold: 25)

        XCTAssertEqual(motionLevel, 0.0)

        let motionThreshold: Float = 0.02
        XCTAssertFalse(motionLevel >= motionThreshold)
    }

    func testSubtleMotionBelowThreshold() {
        let size = 100

        // Frame with very subtle changes (below pixel threshold)
        let frame1 = [UInt8](repeating: 100, count: size)
        var frame2 = [UInt8](repeating: 100, count: size)

        // Small changes that are below the pixel threshold of 25
        for i in 0..<50 {
            frame2[i] = 110  // Only 10 difference, below 25 threshold
        }

        guard let diff = FrameProcessor.absoluteDifference(current: frame2, previous: frame1) else {
            XCTFail("absoluteDifference returned nil")
            return
        }

        let motionLevel = FrameProcessor.motionPercentage(diffBuffer: diff, threshold: 25)

        // Should be 0 because all differences are below threshold
        XCTAssertEqual(motionLevel, 0.0)
    }
}
