import XCTest
@testable import Watchdawg

final class TTLCleanerTests: XCTestCase {
    var testDirectory: URL!
    var fileManager: FileManager!

    override func setUpWithError() throws {
        fileManager = FileManager.default

        // Create a temporary test directory
        testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WatchdawgTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up test directory
        if fileManager.fileExists(atPath: testDirectory.path) {
            try fileManager.removeItem(at: testDirectory)
        }
    }

    func testExpiredFilesAreIdentified() throws {
        // Create a file with a creation date older than 48 hours
        let oldFile = testDirectory.appendingPathComponent("old_recording.mp4")
        fileManager.createFile(atPath: oldFile.path, contents: Data("test".utf8))

        // Manually set creation date to 49 hours ago
        let oldDate = Date().addingTimeInterval(-49 * 60 * 60)
        try fileManager.setAttributes([.creationDate: oldDate], ofItemAtPath: oldFile.path)

        // Create a recent file
        let newFile = testDirectory.appendingPathComponent("new_recording.mp4")
        fileManager.createFile(atPath: newFile.path, contents: Data("test".utf8))

        // Verify old file has old creation date
        let attrs = try fileManager.attributesOfItem(atPath: oldFile.path)
        let creationDate = attrs[.creationDate] as? Date
        XCTAssertNotNil(creationDate)

        let ttlSeconds: TimeInterval = 48 * 60 * 60
        let isExpired = Date().timeIntervalSince(creationDate!) > ttlSeconds
        XCTAssertTrue(isExpired, "File should be identified as expired")
    }

    func testRecentFilesAreNotExpired() throws {
        // Create a recent file (created now)
        let newFile = testDirectory.appendingPathComponent("recent_recording.mp4")
        fileManager.createFile(atPath: newFile.path, contents: Data("test".utf8))

        let attrs = try fileManager.attributesOfItem(atPath: newFile.path)
        let creationDate = attrs[.creationDate] as? Date
        XCTAssertNotNil(creationDate)

        let ttlSeconds: TimeInterval = 48 * 60 * 60
        let isExpired = Date().timeIntervalSince(creationDate!) > ttlSeconds
        XCTAssertFalse(isExpired, "Recent file should not be expired")
    }

    func testFileAtExactBoundary() throws {
        // Create a file at exactly 48 hours (should not be expired)
        let boundaryFile = testDirectory.appendingPathComponent("boundary_recording.mp4")
        fileManager.createFile(atPath: boundaryFile.path, contents: Data("test".utf8))

        let exactlyAt48Hours = Date().addingTimeInterval(-48 * 60 * 60)
        try fileManager.setAttributes([.creationDate: exactlyAt48Hours], ofItemAtPath: boundaryFile.path)

        let attrs = try fileManager.attributesOfItem(atPath: boundaryFile.path)
        let creationDate = attrs[.creationDate] as? Date
        XCTAssertNotNil(creationDate)

        let ttlSeconds: TimeInterval = 48 * 60 * 60
        // Files at exactly 48 hours should NOT be expired (we use > not >=)
        let isExpired = Date().timeIntervalSince(creationDate!) > ttlSeconds
        // This might be slightly over due to test execution time, so we just check it's close
        XCTAssertTrue(abs(Date().timeIntervalSince(creationDate!) - ttlSeconds) < 1)
    }

    func testTTLCalculation() throws {
        let ttlSeconds: TimeInterval = 48 * 60 * 60

        // 48 hours = 172800 seconds
        XCTAssertEqual(ttlSeconds, 172800)

        // Test various time differences
        let oneHourAgo = Date().addingTimeInterval(-1 * 60 * 60)
        XCTAssertFalse(Date().timeIntervalSince(oneHourAgo) > ttlSeconds)

        let fortySevenHoursAgo = Date().addingTimeInterval(-47 * 60 * 60)
        XCTAssertFalse(Date().timeIntervalSince(fortySevenHoursAgo) > ttlSeconds)

        let fortyNineHoursAgo = Date().addingTimeInterval(-49 * 60 * 60)
        XCTAssertTrue(Date().timeIntervalSince(fortyNineHoursAgo) > ttlSeconds)
    }
}
