import AVFoundation
import Combine

struct MotionDetectorConfig {
    /// Pixel difference threshold (0-255) - pixels with diff > threshold are considered changed
    var pixelThreshold: UInt8 = 25

    /// Percentage of pixels that must change to trigger motion (0.0-1.0)
    var motionThreshold: Float = 0.02

    /// Number of consecutive frames required to confirm motion
    var confirmationFrames: Int = 3

    /// Seconds to wait after no motion before stopping recording
    var cooldownSeconds: TimeInterval = 10

    /// Target size for frame analysis (smaller = faster)
    var analysisSize: CGSize = CGSize(width: 160, height: 120)

    /// How many frames per second to analyze (skip others)
    var analysisFrameRate: Int = 5

    static var `default`: MotionDetectorConfig { MotionDetectorConfig() }
}

enum MotionState: String {
    case idle       // Not monitoring
    case monitoring // Watching for motion
    case confirming // Motion detected, waiting for confirmation frames
    case active     // Motion confirmed, recording
    case cooldown   // Motion stopped, waiting before stopping recording
}

protocol MotionDetectorDelegate: AnyObject {
    func motionDetector(_ detector: MotionDetector, motionStarted timestamp: CMTime)
    func motionDetector(_ detector: MotionDetector, motionEnded timestamp: CMTime)
}

@MainActor
final class MotionDetector: NSObject, ObservableObject {
    weak var delegate: MotionDetectorDelegate?
    var config: MotionDetectorConfig

    @Published private(set) var state: MotionState = .idle
    @Published private(set) var isMotionDetected: Bool = false
    @Published private(set) var currentMotionLevel: Float = 0.0

    private var previousFrame: [UInt8]?
    private var consecutiveMotionFrames: Int = 0
    private var cooldownTimer: Timer?
    private var lastAnalysisTime: CFAbsoluteTime = 0
    private let analysisInterval: TimeInterval

    private let processingQueue = DispatchQueue(label: "com.watchdawg.motiondetector", qos: .userInteractive)

    init(config: MotionDetectorConfig = .default) {
        self.config = config
        self.analysisInterval = 1.0 / Double(config.analysisFrameRate)
        super.init()
    }

    // MARK: - Public Control

    func startMonitoring() {
        previousFrame = nil
        consecutiveMotionFrames = 0
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        state = .monitoring
        isMotionDetected = false
        currentMotionLevel = 0.0
    }

    func stopMonitoring() {
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        previousFrame = nil
        consecutiveMotionFrames = 0
        state = .idle
        isMotionDetected = false
        currentMotionLevel = 0.0
    }

    // MARK: - Frame Processing

    nonisolated func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // Rate limit analysis
        let currentTime = CFAbsoluteTimeGetCurrent()

        // Extract pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        processingQueue.async { [weak self] in
            self?.analyzeFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, currentTime: currentTime)
        }
    }

    nonisolated private func analyzeFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime, currentTime: CFAbsoluteTime) {
        // Get config values (these are value types so safe to read)
        let analysisSize = CGSize(width: 160, height: 120)
        let pixelThreshold: UInt8 = 25

        // Convert to grayscale
        guard let currentFrame = FrameProcessor.toGrayscale(pixelBuffer: pixelBuffer, targetSize: analysisSize) else {
            return
        }

        // Calculate motion on background thread, then update state on main
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Rate limit on main actor where lastAnalysisTime lives
            guard currentTime - lastAnalysisTime >= analysisInterval else {
                return
            }
            lastAnalysisTime = currentTime

            // Need previous frame to compare
            guard let previous = previousFrame else {
                previousFrame = currentFrame
                return
            }

            // Calculate difference
            guard let diffBuffer = FrameProcessor.absoluteDifference(current: currentFrame, previous: previous) else {
                previousFrame = currentFrame
                return
            }

            // Calculate motion percentage
            let motionLevel = FrameProcessor.motionPercentageOptimized(diffBuffer: diffBuffer, threshold: config.pixelThreshold)

            // Update previous frame
            previousFrame = currentFrame

            // Update state based on motion level
            updateState(motionLevel: motionLevel, timestamp: timestamp)
        }
    }

    private func updateState(motionLevel: Float, timestamp: CMTime) {
        currentMotionLevel = motionLevel

        let motionDetected = motionLevel >= config.motionThreshold

        switch state {
        case .idle:
            // Not monitoring, ignore
            break

        case .monitoring:
            if motionDetected {
                consecutiveMotionFrames = 1
                state = .confirming
            }

        case .confirming:
            if motionDetected {
                consecutiveMotionFrames += 1
                if consecutiveMotionFrames >= config.confirmationFrames {
                    // Motion confirmed!
                    state = .active
                    isMotionDetected = true
                    delegate?.motionDetector(self, motionStarted: timestamp)
                }
            } else {
                // False alarm, go back to monitoring
                consecutiveMotionFrames = 0
                state = .monitoring
            }

        case .active:
            if motionDetected {
                // Still active, reset any cooldown
                cooldownTimer?.invalidate()
                cooldownTimer = nil
            } else {
                // No motion, start cooldown
                state = .cooldown
                startCooldownTimer(timestamp: timestamp)
            }

        case .cooldown:
            if motionDetected {
                // Motion resumed, go back to active
                cooldownTimer?.invalidate()
                cooldownTimer = nil
                state = .active
            }
            // If no motion, cooldown timer will handle transition
        }
    }

    private func startCooldownTimer(timestamp: CMTime) {
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: config.cooldownSeconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Cooldown expired, motion ended
                self.state = .monitoring
                self.isMotionDetected = false
                self.consecutiveMotionFrames = 0
                self.delegate?.motionDetector(self, motionEnded: timestamp)
            }
        }
    }

    // MARK: - Configuration Updates

    func updateConfig(_ newConfig: MotionDetectorConfig) {
        config = newConfig
    }

    func updateMotionThreshold(_ threshold: Float) {
        config.motionThreshold = threshold
    }

    func updateCooldownSeconds(_ seconds: Int) {
        config.cooldownSeconds = TimeInterval(seconds)
    }
}
