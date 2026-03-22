import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storage = RecordingStorage.shared
    @ObservedObject private var cleaner = TTLCleaner.shared

    @State private var showClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                qualitySection
                sentryModeSection
                notificationsSection
                storageSection
                autoDeleteSection
                aboutSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Clear All Recordings?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                storage.delete(storage.recordings)
            }
        } message: {
            Text("This will permanently delete all \(storage.recordings.count) recordings. This cannot be undone.")
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        SettingsCard(title: "Video Quality", icon: "camera.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Recording Quality", selection: Binding(
                    get: { appState.currentQuality },
                    set: { appState.setQuality($0) }
                )) {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        Text(quality.description).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Text("Lower quality uses less storage but may reduce clarity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sentry Mode Section

    private var sentryModeSection: some View {
        SettingsCard(title: "Sentry Mode", icon: "eye.fill") {
            VStack(spacing: 12) {
                Toggle("Enable Sentry Mode", isOn: Binding(
                    get: { appState.sentryModeEnabled },
                    set: { appState.setSentryModeEnabled($0) }
                ))

                Text("Only record when motion is detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Motion Sensitivity")
                        .font(.subheadline)

                    Slider(value: Binding(
                        get: { Double(appState.motionSensitivity) },
                        set: { appState.setMotionSensitivity(Float($0)) }
                    ), in: 0.01...0.10)

                    HStack {
                        Text("Low")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.motionSensitivity * 100))%")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("High")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(appState.sentryModeEnabled ? 1.0 : 0.5)

                Divider()

                SettingsRow(label: "Stop After No Motion") {
                    Picker("", selection: Binding(
                        get: { appState.motionCooldown },
                        set: { appState.setMotionCooldown($0) }
                    )) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                    }
                    .pickerStyle(.menu)
                    .disabled(!appState.sentryModeEnabled)
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        SettingsCard(title: "Notifications", icon: "bell.fill") {
            VStack(spacing: 12) {
                Toggle("Enable Notifications", isOn: Binding(
                    get: { appState.notificationsEnabled },
                    set: { appState.setNotificationsEnabled($0) }
                ))

                Divider()

                Toggle("Notification Sound", isOn: Binding(
                    get: { appState.notificationSoundEnabled },
                    set: { appState.setNotificationSoundEnabled($0) }
                ))
                .disabled(!appState.notificationsEnabled)
            }
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        SettingsCard(title: "Storage", icon: "externaldrive.fill") {
            VStack(spacing: 12) {
                SettingsRow(label: "Location") {
                    HStack(spacing: 8) {
                        Text(storage.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storage.recordingsDirectory.path)
                        } label: {
                            Image(systemName: "folder")
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Divider()

                SettingsRow(label: "Total Storage Used") {
                    Text(formatBytes(storage.totalStorageUsed))
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsRow(label: "Recording Count") {
                    Text("\(storage.recordings.count)")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Spacer()
                    Button { showClearConfirmation = true } label: {
                        Label("Clear All Recordings", systemImage: "trash")
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accent.opacity(storage.recordings.isEmpty ? 0.5 : 1.0))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(storage.recordings.isEmpty)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Auto-Delete Section

    private var autoDeleteSection: some View {
        SettingsCard(title: "Auto-Delete", icon: "clock.arrow.circlepath") {
            VStack(spacing: 12) {
                SettingsRow(label: "Retention Period") {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundStyle(Theme.accent)
                        Text("48 hours")
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastCleanup = cleaner.lastCleanupDate {
                    Divider()
                    SettingsRow(label: "Last Cleanup") {
                        Text(lastCleanup, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }

                if let timeUntilNext = cleaner.nextExpiration {
                    Divider()
                    SettingsRow(label: "Next Expiration") {
                        Text(formatDuration(timeUntilNext))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                SettingsRow(label: "Files Auto-Deleted") {
                    Text("\(cleaner.filesDeleted)")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Spacer()
                    Button { cleaner.cleanExpiredRecordings() } label: {
                        Label("Run Cleanup Now", systemImage: "arrow.clockwise")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsCard(title: "About", icon: "info.circle.fill") {
            VStack(spacing: 12) {
                SettingsRow(label: "Version") {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Spacer()
                    Button { NSWorkspace.shared.open(storage.recordingsDirectory) } label: {
                        Label("Open Recordings Folder", systemImage: "folder")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Formatters

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
                .labelStyle(AccentIconLabelStyle())

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

private struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
        }
    }
}
