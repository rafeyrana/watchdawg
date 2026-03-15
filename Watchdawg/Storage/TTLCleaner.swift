import Foundation

final class TTLCleaner: ObservableObject {
    static let shared = TTLCleaner()

    @Published private(set) var lastCleanupDate: Date?
    @Published private(set) var filesDeleted = 0

    private var cleanupTimer: Timer?

    private static let ttl: TimeInterval = 48 * 60 * 60
    private static let cleanupInterval: TimeInterval = 60 * 60

    private init() {}

    func startPeriodicCleanup() {
        Task { @MainActor in
            cleanExpiredRecordings()
        }

        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: Self.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleanExpiredRecordings()
            }
        }
    }

    func stopPeriodicCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    @MainActor
    func cleanExpiredRecordings() {
        let storage = RecordingStorage.shared
        let now = Date()

        let expired = storage.recordings.filter {
            now.timeIntervalSince($0.createdAt) > Self.ttl
        }

        guard !expired.isEmpty else {
            lastCleanupDate = now
            return
        }

        storage.delete(expired)
        filesDeleted += expired.count
        lastCleanupDate = now
    }

    var expiredCount: Int {
        let now = Date()
        return RecordingStorage.shared.recordings.filter {
            now.timeIntervalSince($0.createdAt) > Self.ttl
        }.count
    }

    var nextExpiration: TimeInterval? {
        guard let oldest = RecordingStorage.shared.recordings
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first else {
            return nil
        }

        let expirationDate = oldest.createdAt.addingTimeInterval(Self.ttl)
        let remaining = expirationDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}
