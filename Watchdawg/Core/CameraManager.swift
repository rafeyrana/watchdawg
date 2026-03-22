import AVFoundation

enum CameraError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case cameraAccessDenied
    case microphoneAccessDenied
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "No camera available"
        case .microphoneUnavailable: return "No microphone available"
        case .cameraAccessDenied: return "Camera access denied"
        case .microphoneAccessDenied: return "Microphone access denied"
        case .configurationFailed: return "Configuration failed"
        }
    }
}

final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isMotionActive = false
    @Published var sentryModeEnabled = false

    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.watchdawg.camera")
    private let videoDataQueue = DispatchQueue(label: "com.watchdawg.videodata", qos: .userInteractive)
    private var chunkTimer: Timer?
    private var isConfigured = false
    private var isSentryConfigured = false

    private(set) var motionDetector: MotionDetector?

    private static let chunkDuration: TimeInterval = 5 * 60
    private static let recordingFinalizationDelay: TimeInterval = 0.5

    private override init() {
        super.init()
    }

    // MARK: - Permissions

    func requestPermissions() async throws {
        try await requestCameraAccess()
        try await requestMicrophoneAccess()
    }

    private func requestCameraAccess() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CameraError.cameraAccessDenied
            }
        default:
            throw CameraError.cameraAccessDenied
        }
    }

    private func requestMicrophoneAccess() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw CameraError.microphoneAccessDenied
            }
        default:
            throw CameraError.microphoneAccessDenied
        }
    }

    // MARK: - Configuration

    func configure(quality: VideoQuality) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }

                guard !isConfigured else {
                    continuation.resume(returning: ())
                    return
                }

                do {
                    try configureSession(quality: quality)
                    isConfigured = true
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureSession(quality: VideoQuality) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = quality.capturePreset

        try addVideoInput()
        try addAudioInput()
        addMovieOutput()
    }

    private func addVideoInput() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
    }

    private func addAudioInput() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.microphoneUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
    }

    private func addMovieOutput() {
        let output = AVCaptureMovieFileOutput()
        output.maxRecordedDuration = CMTime(seconds: 300, preferredTimescale: 600)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        movieOutput = output
    }

    // MARK: - Sentry Mode Configuration

    func configureSentryMode(config: MotionDetectorConfig) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard !isSentryConfigured else { return }

            session.beginConfiguration()

            // Add video data output for frame analysis
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoDataQueue)

            if session.canAddOutput(output) {
                session.addOutput(output)
                videoDataOutput = output
            }

            session.commitConfiguration()

            // Initialize motion detector on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let detector = MotionDetector(config: config)
                detector.delegate = self
                motionDetector = detector
                isSentryConfigured = true
            }
        }
    }

    func updateSentryConfig(motionThreshold: Float? = nil, cooldownSeconds: Int? = nil) {
        Task { @MainActor in
            if let threshold = motionThreshold {
                motionDetector?.updateMotionThreshold(threshold)
            }
            if let cooldown = cooldownSeconds {
                motionDetector?.updateCooldownSeconds(cooldown)
            }
        }
    }

    // MARK: - Session Control

    func start() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self, !session.isRunning else {
                    continuation.resume(returning: ())
                    return
                }

                session.startRunning()

                DispatchQueue.main.async {
                    self.isRunning = true
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func stop() {
        if movieOutput?.isRecording == true {
            stopRecording()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + Self.recordingFinalizationDelay
            ) { [weak self] in
                self?.stopSession()
            }
        } else {
            stopSession()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if session.isRunning {
                session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    // MARK: - Sentry Mode Control

    func startSentryMode(motionSensitivity: Float, motionCooldown: Int) {
        guard sentryModeEnabled else { return }

        // Configure sentry if not already done
        if !isSentryConfigured {
            let config = MotionDetectorConfig(
                motionThreshold: motionSensitivity,
                cooldownSeconds: TimeInterval(motionCooldown)
            )
            configureSentryMode(config: config)
        }

        // Start monitoring after a brief delay to ensure configuration is complete
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            motionDetector?.startMonitoring()
        }
    }

    func stopSentryMode() {
        Task { @MainActor in
            motionDetector?.stopMonitoring()
        }
        if isRecording {
            stopRecording()
        }
        isMotionActive = false
    }

    // MARK: - Recording

    func startRecording() {
        guard let output = movieOutput,
              !isRecording,
              session.isRunning else { return }

        let url = makeRecordingURL()
        isRecording = true
        startChunkTimer()
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        chunkTimer?.invalidate()
        chunkTimer = nil

        guard let output = movieOutput, output.isRecording else {
            isRecording = false
            return
        }

        isRecording = false
        output.stopRecording()
    }

    // MARK: - Chunking

    private func startChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(
            withTimeInterval: Self.chunkDuration,
            repeats: true
        ) { [weak self] _ in
            self?.rotateChunk()
        }
    }

    private func rotateChunk() {
        sessionQueue.async { [weak self] in
            guard let self, isRecording, let output = movieOutput else { return }

            output.stopRecording()

            sessionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, isRecording, let output = movieOutput else { return }
                output.startRecording(to: makeRecordingURL(), recordingDelegate: self)
            }
        }
    }

    private func makeRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: Date())).mp4"
        return RecordingStorage.shared.recordingsDirectory.appendingPathComponent(filename)
    }
}

// MARK: - Recording Delegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {}

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        guard error == nil else { return }

        Task { @MainActor in
            await saveRecording(at: outputFileURL)
        }
    }

    @MainActor
    private func saveRecording(at url: URL) async {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path),
              let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize > 0 else { return }

        let asset = AVAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0

        let recording = Recording(
            filename: url.lastPathComponent,
            createdAt: Date(),
            duration: duration,
            fileSize: fileSize,
            quality: AppState.shared.currentQuality
        )

        RecordingStorage.shared.add(recording)
    }
}

// MARK: - Video Data Output Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Only process frames when sentry mode is enabled
        guard sentryModeEnabled else { return }
        motionDetector?.processFrame(sampleBuffer)
    }
}

// MARK: - Motion Detector Delegate

extension CameraManager: MotionDetectorDelegate {
    func motionDetector(_ detector: MotionDetector, motionStarted timestamp: CMTime) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isMotionActive = true

            // Start recording if not already recording
            if !isRecording {
                startRecording()
                NotificationManager.shared.sendMotionDetectedNotification()
            }
        }
    }

    func motionDetector(_ detector: MotionDetector, motionEnded timestamp: CMTime) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isMotionActive = false

            // Stop recording when motion ends (in sentry mode)
            if isRecording && sentryModeEnabled {
                stopRecording()
            }
        }
    }
}
