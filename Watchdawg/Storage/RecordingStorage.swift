import Foundation

final class RecordingStorage: ObservableObject {
    static let shared = RecordingStorage()

    @Published private(set) var recordings: [Recording] = []

    let recordingsDirectory: URL
    private let metadataURL: URL
    private let fileManager = FileManager.default

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("Watchdawg", isDirectory: true)

        recordingsDirectory = appDirectory.appendingPathComponent("recordings", isDirectory: true)
        metadataURL = appDirectory.appendingPathComponent("metadata.json")

        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        loadMetadata()
    }

    // MARK: - Public API

    @MainActor
    func add(_ recording: Recording) {
        recordings.removeAll { $0.filename == recording.filename }
        recordings.insert(recording, at: 0)
        persistMetadata()
    }

    @MainActor
    func delete(_ recording: Recording) {
        try? fileManager.removeItem(at: recording.url)
        recordings.removeAll { $0.id == recording.id }
        persistMetadata()
    }

    @MainActor
    func delete(_ recordingsToDelete: [Recording]) {
        let idsToDelete = Set(recordingsToDelete.map(\.id))
        recordingsToDelete.forEach { try? fileManager.removeItem(at: $0.url) }
        recordings.removeAll { idsToDelete.contains($0.id) }
        persistMetadata()
    }

    @MainActor
    func refresh() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        let existingFilenames = Set(fileURLs.map(\.lastPathComponent))

        var updated = recordings.filter { existingFilenames.contains($0.filename) }
        updated = removeDuplicates(from: updated)

        let knownFilenames = Set(updated.map(\.filename))
        let newRecordings = fileURLs
            .filter { !knownFilenames.contains($0.lastPathComponent) }
            .compactMap { createRecording(from: $0) }

        updated.append(contentsOf: newRecordings)
        updated.sort { $0.createdAt > $1.createdAt }

        recordings = updated
        persistMetadata()
    }

    var totalStorageUsed: Int64 {
        recordings.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Private

    private func loadMetadata() {
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(RecordingMetadata.self, from: data) else {
            return
        }
        recordings = metadata.recordings
    }

    private func persistMetadata() {
        let metadata = RecordingMetadata(recordings: recordings)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func createRecording(from url: URL) -> Recording? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let creationDate = attrs[.creationDate] as? Date,
              let fileSize = attrs[.size] as? Int64 else {
            return nil
        }

        return Recording(
            filename: url.lastPathComponent,
            createdAt: creationDate,
            duration: 0,
            fileSize: fileSize,
            quality: .medium
        )
    }

    private func removeDuplicates(from recordings: [Recording]) -> [Recording] {
        var seen: [String: Recording] = [:]

        for recording in recordings {
            if let existing = seen[recording.filename] {
                if recording.duration > existing.duration || recording.fileSize > existing.fileSize {
                    seen[recording.filename] = recording
                }
            } else {
                seen[recording.filename] = recording
            }
        }

        return Array(seen.values)
    }
}
