import SwiftUI
import AVFoundation

struct RecordingsView: View {
    @ObservedObject private var storage = RecordingStorage.shared
    @State private var selection: Recording?
    @State private var deleteConfirmation: Recording?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .onAppear {
            storage.refresh()
            TTLCleaner.shared.cleanExpiredRecordings()
        }
        .confirmationDialog(
            "Delete Recording?",
            isPresented: .init(
                get: { deleteConfirmation != nil },
                set: { if !$0 { deleteConfirmation = nil } }
            ),
            presenting: deleteConfirmation
        ) { recording in
            Button("Delete", role: .destructive) {
                storage.delete(recording)
                if selection?.id == recording.id {
                    selection = nil
                }
            }
        } message: { recording in
            Text("Delete \"\(recording.filename)\"? This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            recordingsList
        }
        .frame(minWidth: 280)
    }

    private var header: some View {
        HStack {
            Text("Recordings")
                .font(.headline)
            Spacer()
            Button { storage.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var recordingsList: some View {
        if storage.recordings.isEmpty {
            emptyState
        } else {
            List(storage.recordings, selection: $selection) { recording in
                RecordingRow(recording: recording, isSelected: selection == recording)
                    .tag(recording)
                    .contextMenu { contextMenu(for: recording) }
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Recordings Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start watching to create recordings")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for recording: Recording) -> some View {
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(recording.url.path, inFileViewerRootedAtPath: "")
        }
        Divider()
        Button("Delete", role: .destructive) {
            deleteConfirmation = recording
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let recording = selection {
            PlayerView(recording: recording)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a Recording")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose a recording from the list to play it")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Recording Row

private struct RecordingRow: View {
    let recording: Recording
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.formattedDate)
                .font(.headline)
                .foregroundStyle(isSelected ? Theme.accent : .primary)

            HStack(spacing: 12) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label(recording.formattedFileSize, systemImage: "doc")
                Label(recording.quality.rawValue, systemImage: "camera")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - Player View

private struct PlayerView: View {
    let recording: Recording

    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            videoArea
            infoBar
        }
        .task(id: recording.id) {
            await loadVideo()
        }
    }

    private var videoArea: some View {
        ZStack {
            Color.black

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            } else if let player {
                VideoSurface(player: player)
            } else {
                Text("Unable to load video")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var infoBar: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                Text(recording.formattedDate)
                    .fontWeight(.medium)
            }

            Spacer()

            HStack(spacing: 16) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label(recording.formattedFileSize, systemImage: "doc")
                Label(recording.quality.description, systemImage: "camera")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func loadVideo() async {
        isLoading = true
        player?.pause()
        player = nil

        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            isLoading = false
            return
        }

        let newPlayer = AVPlayer(url: recording.url)
        player = newPlayer
        isLoading = false
        newPlayer.play()
    }
}

// MARK: - Video Surface

private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: VideoLayerView, context: Context) {
        nsView.player = player
    }
}

private final class VideoLayerView: NSView {
    private var playerLayer: AVPlayerLayer?

    var player: AVPlayer? {
        didSet {
            setupLayerIfNeeded()
            playerLayer?.player = player
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayerIfNeeded() {
        guard playerLayer == nil else { return }

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        self.layer?.addSublayer(layer)
        playerLayer = layer
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}
