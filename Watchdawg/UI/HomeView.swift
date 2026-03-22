import SwiftUI
import AVFoundation

struct HomeView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var camera = CameraManager.shared

    @State private var error: String?
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 16) {
            header
            preview
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("🐕")
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text("Watchdawg")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Home Security Camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(camera.isRecording ? Theme.accent : .gray)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(camera.isRecording ? Theme.accent : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
    }

    private var statusText: String {
        if camera.isRecording { return "Recording" }
        if appState.isArmed && appState.sentryModeEnabled { return "Watching" }
        if appState.isArmed { return "Armed" }
        return "Idle"
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { geometry in
            Group {
                if appState.isArmed {
                    ZStack {
                        CameraSurface(session: camera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.accent, lineWidth: 2)
                            )

                        motionOverlay
                    }
                } else {
                    previewPlaceholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var motionOverlay: some View {
        if appState.sentryModeEnabled && camera.isMotionActive {
            VStack {
                HStack {
                    Spacer()
                    Label("Motion!", systemImage: "figure.walk.motion")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                        .foregroundColor(.white)
                        .padding(8)
                }
                Spacer()
            }
        }
    }

    private var previewPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Camera Preview")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click Start Watching to begin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            qualityPicker
            actionButton

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var qualityPicker: some View {
        HStack(spacing: 12) {
            Text("Quality:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { appState.currentQuality },
                set: { appState.setQuality($0) }
            )) {
                Text("Low").tag(VideoQuality.low)
                Text("Medium").tag(VideoQuality.medium)
                Text("High").tag(VideoQuality.high)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(appState.isArmed)
        }
    }

    private var actionButton: some View {
        Button(action: toggleWatching) {
            HStack(spacing: 10) {
                if isStarting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: appState.isArmed ? "stop.fill" : "play.fill")
                }

                Text(appState.isArmed ? "Stop Watching" : "Start Watching")
                    .font(.headline)
            }
            .frame(width: 180)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(appState.isArmed ? .gray : Theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
    }

    // MARK: - Actions

    private func toggleWatching() {
        if appState.isArmed {
            stopWatching()
        } else {
            startWatching()
        }
    }

    private func startWatching() {
        isStarting = true
        error = nil

        Task {
            do {
                try await camera.requestPermissions()
                try await camera.configure(quality: appState.currentQuality)
                await camera.start()

                appState.arm()
                isStarting = false

                try await Task.sleep(for: .seconds(1))

                if appState.sentryModeEnabled {
                    // Sentry mode: start motion detection, recording starts on motion
                    camera.startSentryMode(
                        motionSensitivity: appState.motionSensitivity,
                        motionCooldown: appState.motionCooldown
                    )
                } else {
                    // Normal mode: start continuous recording
                    camera.startRecording()
                }

                TTLCleaner.shared.startPeriodicCleanup()
            } catch {
                self.error = error.localizedDescription
                isStarting = false
            }
        }
    }

    private func stopWatching() {
        if appState.sentryModeEnabled {
            camera.stopSentryMode()
        }
        camera.stop()
        appState.disarm()
    }
}

// MARK: - Camera Surface

private struct CameraSurface: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CameraLayerView, context: Context) {
        nsView.session = session
    }
}

private final class CameraLayerView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? {
        didSet {
            guard oldValue !== session else { return }
            setupPreviewLayer()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        guard let session else { return }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        previewLayer = layer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
