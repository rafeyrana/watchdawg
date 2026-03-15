import Foundation

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let createdAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let quality: VideoQuality

    var url: URL {
        RecordingStorage.shared.recordingsDirectory.appendingPathComponent(filename)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    init(id: UUID = UUID(), filename: String, createdAt: Date, duration: TimeInterval, fileSize: Int64, quality: VideoQuality) {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
        self.duration = duration
        self.fileSize = fileSize
        self.quality = quality
    }
}

struct RecordingMetadata: Codable {
    var recordings: [Recording]

    init(recordings: [Recording] = []) {
        self.recordings = recordings
    }
}
