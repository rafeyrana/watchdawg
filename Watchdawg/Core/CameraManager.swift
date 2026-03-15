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

    private var movieOutput: AVCaptureMovieFileOutput?
    private let sessionQueue = DispatchQueue(label: "com.watchdawg.camera")
    private var chunkTimer: Timer?
    private var isConfigured = false

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
