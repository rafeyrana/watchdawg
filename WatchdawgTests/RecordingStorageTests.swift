import XCTest
@testable import Watchdawg

final class RecordingStorageTests: XCTestCase {
    var testDirectory: URL!
    var fileManager: FileManager!

    override func setUpWithError() throws {
        fileManager = FileManager.default

        // Create a temporary test directory
        testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WatchdawgStorageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up test directory
        if fileManager.fileExists(atPath: testDirectory.path) {
            try fileManager.removeItem(at: testDirectory)
        }
    }

    func testRecordingModelCreation() throws {
        let recording = Recording(
            filename: "2025-03-14_14-30-00.mp4",
            createdAt: Date(),
            duration: 300, // 5 minutes
            fileSize: 10_000_000, // 10 MB
            quality: .medium
        )

        XCTAssertEqual(recording.filename, "2025-03-14_14-30-00.mp4")
        XCTAssertEqual(recording.duration, 300)
        XCTAssertEqual(recording.fileSize, 10_000_000)
        XCTAssertEqual(recording.quality, .medium)
    }

    func testRecordingFormattedDuration() throws {
        let recording = Recording(
            filename: "test.mp4",
            createdAt: Date(),
            duration: 185, // 3:05
            fileSize: 1000,
            quality: .low
        )

        XCTAssertEqual(recording.formattedDuration, "3:05")
    }

    func testRecordingFormattedDurationShort() throws {
        let recording = Recording(
            filename: "test.mp4",
            createdAt: Date(),
            duration: 45, // 0:45
            fileSize: 1000,
            quality: .low
        )

        XCTAssertEqual(recording.formattedDuration, "0:45")
    }

    func testRecordingFormattedFileSize() throws {
        let recording = Recording(
            filename: "test.mp4",
            createdAt: Date(),
            duration: 100,
            fileSize: 15_000_000, // ~15 MB
            quality: .high
        )

        // ByteCountFormatter output may vary, just check it contains MB
        XCTAssertTrue(recording.formattedFileSize.contains("MB") || recording.formattedFileSize.contains("GB"))
    }

    func testRecordingMetadataEncodeDecode() throws {
        let recording1 = Recording(
            filename: "test1.mp4",
            createdAt: Date(),
            duration: 100,
            fileSize: 1000,
            quality: .low
        )

        let recording2 = Recording(
            filename: "test2.mp4",
            createdAt: Date(),
            duration: 200,
            fileSize: 2000,
            quality: .high
        )

        let metadata = RecordingMetadata(recordings: [recording1, recording2])

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RecordingMetadata.self, from: data)

        XCTAssertEqual(decoded.recordings.count, 2)
        XCTAssertEqual(decoded.recordings[0].filename, "test1.mp4")
        XCTAssertEqual(decoded.recordings[1].filename, "test2.mp4")
    }

    func testVideoQualityPresets() {
        XCTAssertEqual(VideoQuality.low.rawValue, "Low")
        XCTAssertEqual(VideoQuality.medium.rawValue, "Medium")
        XCTAssertEqual(VideoQuality.high.rawValue, "High")

        // Test descriptions
        XCTAssertTrue(VideoQuality.low.description.contains("352x288"))
        XCTAssertTrue(VideoQuality.medium.description.contains("480p"))
        XCTAssertTrue(VideoQuality.high.description.contains("720p"))
    }

    func testDirectoryCreation() throws {
        let recordingsDir = testDirectory.appendingPathComponent("recordings", isDirectory: true)

        // Directory should not exist initially
        XCTAssertFalse(fileManager.fileExists(atPath: recordingsDir.path))

        // Create it
        try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        // Now it should exist
        XCTAssertTrue(fileManager.fileExists(atPath: recordingsDir.path))
    }

    func testFileSizeCalculation() throws {
        let testFile = testDirectory.appendingPathComponent("test.mp4")
        let testData = Data(repeating: 0, count: 1024 * 1024) // 1 MB
        try testData.write(to: testFile)

        let attrs = try fileManager.attributesOfItem(atPath: testFile.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        XCTAssertEqual(fileSize, 1024 * 1024)
    }

    func testTotalStorageCalculation() throws {
        let recordings = [
            Recording(filename: "a.mp4", createdAt: Date(), duration: 100, fileSize: 1000, quality: .low),
            Recording(filename: "b.mp4", createdAt: Date(), duration: 200, fileSize: 2000, quality: .medium),
            Recording(filename: "c.mp4", createdAt: Date(), duration: 300, fileSize: 3000, quality: .high)
        ]

        let totalSize = recordings.reduce(0) { $0 + $1.fileSize }
        XCTAssertEqual(totalSize, 6000)
    }

    // MARK: - Recording Model Edge Cases

    func testRecordingFormattedDurationHours() throws {
        // Test duration over 1 hour (65 minutes = 65:00)
        let recording = Recording(
            filename: "long.mp4",
            createdAt: Date(),
            duration: 3900, // 65 minutes
            fileSize: 1000,
            quality: .high
        )

        XCTAssertEqual(recording.formattedDuration, "65:00")
    }

    func testRecordingFormattedDurationZero() throws {
        let recording = Recording(
            filename: "empty.mp4",
            createdAt: Date(),
            duration: 0,
            fileSize: 1000,
            quality: .low
        )

        XCTAssertEqual(recording.formattedDuration, "0:00")
    }

    func testRecordingFormattedFileSizeBytes() throws {
        let recording = Recording(
            filename: "tiny.mp4",
            createdAt: Date(),
            duration: 1,
            fileSize: 500, // 500 bytes
            quality: .low
        )

        // ByteCountFormatter handles small sizes
        XCTAssertFalse(recording.formattedFileSize.isEmpty)
    }

    func testRecordingFormattedFileSizeGigabytes() throws {
        let recording = Recording(
            filename: "huge.mp4",
            createdAt: Date(),
            duration: 3600,
            fileSize: 2_000_000_000, // 2 GB
            quality: .high
        )

        XCTAssertTrue(recording.formattedFileSize.contains("GB"))
    }

    func testRecordingEquality() throws {
        let id = UUID()
        let date = Date()

        let recording1 = Recording(
            id: id,
            filename: "test.mp4",
            createdAt: date,
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        let recording2 = Recording(
            id: id,
            filename: "test.mp4",
            createdAt: date,
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        XCTAssertEqual(recording1, recording2)
        XCTAssertEqual(recording1.hashValue, recording2.hashValue)
    }

    func testRecordingInequalityDifferentIDs() throws {
        let date = Date()

        let recording1 = Recording(
            filename: "test.mp4",
            createdAt: date,
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        let recording2 = Recording(
            filename: "test.mp4",
            createdAt: date,
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        // Different UUIDs generated
        XCTAssertNotEqual(recording1, recording2)
    }

    func testRecordingFormattedDate() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = 15
        components.minute = 30

        let date = calendar.date(from: components)!

        let recording = Recording(
            filename: "test.mp4",
            createdAt: date,
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        // Format depends on locale, just check it's not empty
        XCTAssertFalse(recording.formattedDate.isEmpty)
        // Should contain the year or some date info
        XCTAssertTrue(recording.formattedDate.contains("2026") || recording.formattedDate.contains("Mar") || recording.formattedDate.contains("14"))
    }

    // MARK: - RecordingMetadata Tests

    func testRecordingMetadataEmptyInit() throws {
        let metadata = RecordingMetadata()
        XCTAssertEqual(metadata.recordings.count, 0)
    }

    func testRecordingMetadataWithRecordings() throws {
        let recording = Recording(
            filename: "test.mp4",
            createdAt: Date(),
            duration: 100,
            fileSize: 1000,
            quality: .medium
        )

        let metadata = RecordingMetadata(recordings: [recording])
        XCTAssertEqual(metadata.recordings.count, 1)
        XCTAssertEqual(metadata.recordings[0].filename, "test.mp4")
    }

    // MARK: - VideoQuality Tests

    func testVideoQualityCapturePresets() {
        // Verify capture presets are valid AVCaptureSession presets
        XCTAssertNotNil(VideoQuality.low.capturePreset)
        XCTAssertNotNil(VideoQuality.medium.capturePreset)
        XCTAssertNotNil(VideoQuality.high.capturePreset)
    }

    func testVideoQualityAllCases() {
        let allCases: [VideoQuality] = [.low, .medium, .high]
        XCTAssertEqual(allCases.count, 3)
    }

    func testVideoQualityCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for quality in [VideoQuality.low, .medium, .high] {
            let data = try encoder.encode(quality)
            let decoded = try decoder.decode(VideoQuality.self, from: data)
            XCTAssertEqual(decoded, quality)
        }
    }
}
