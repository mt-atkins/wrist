import XCTest
@testable import Wrist

final class PersistenceTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("memos.json")
    }

    func testMissingIsEmptyButCorruptionThrowsWithoutChangingBytes() throws {
        let url = try temporaryURL()
        XCTAssertNil(try DurableState.load(MemoArchive.self, from: url))
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try DurableState.load(MemoArchive.self, from: url))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testLegacyMigrationDeduplicatesAndRetainsCapture() throws {
        let memo = Memo(source: .sample, transcript: "hello")
        let legacy = try JSONEncoder().encode([memo, memo])
        let archive = try JSONDecoder().decode(MemoArchive.self, from: legacy)
        XCTAssertEqual(archive.memos, [memo])
        XCTAssertTrue(archive.deletedIDs.isEmpty)
    }

    func testTombstonesSurviveReloadAndSuppressStaleRows() throws {
        let url = try temporaryURL()
        let memo = Memo(source: .watchNote, transcript: "deleted")
        try DurableState.save(MemoArchive(memos: [memo], deletedIDs: [memo.id]), to: url)
        let loaded = try XCTUnwrap(DurableState.load(MemoArchive.self, from: url))
        XCTAssertTrue(loaded.memos.isEmpty)
        XCTAssertEqual(loaded.deletedIDs, [memo.id])
    }

    func testOutboxRetainsStableIdentityAndAudioAcrossReload() throws {
        let url = try temporaryURL()
        let audio = PendingCapture(id: UUID(), createdAt: Date(), duration: 3, audioFileName: "capture.m4a")
        let note = PendingCapture(id: UUID(), createdAt: Date(), duration: 0, text: "remember")
        try DurableState.save([audio, note], to: url)
        let loaded = try XCTUnwrap(DurableState.load([PendingCapture].self, from: url))
        XCTAssertEqual(loaded.map(\.id), [audio.id, note.id])
        XCTAssertEqual(loaded.first?.audioFileName, "capture.m4a")
        XCTAssertEqual(loaded.last?.metadata[WristLink.text] as? String, "remember")
        XCTAssertEqual(loaded.first?.metadata[WristLink.memoID] as? String, audio.id.uuidString)
    }

    @MainActor
    func testCorruptStoreRefusesIngestionAndPreservesOriginal() throws {
        let url = try temporaryURL()
        let original = Data("{broken".utf8)
        try original.write(to: url)
        let store = MemoStore(fileURL: url)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.ingestNote("must not overwrite"))
        store.delete(UUID())
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testFailedSaveDoesNotPublishUncommittedCapture() throws {
        let url = try temporaryURL()
        let store = MemoStore(fileURL: url)
        // Replacing a directory with an atomic file write must fail even as root.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.ingestNote("unsaved"))
        XCTAssertNotNil(store.storageError)
        XCTAssertTrue(store.memos.isEmpty)
    }

    @MainActor
    func testDeletionIsDurableAndDuplicateReplayDoesNotResurrect() throws {
        let url = try temporaryURL()
        let memo = Memo(source: .watchNote, status: .ready, transcript: "once")
        try DurableState.save(MemoArchive(memos: [memo]), to: url)
        let store = MemoStore(fileURL: url)
        XCTAssertTrue(store.ingestNote("duplicate", id: memo.id))
        XCTAssertEqual(store.memos.count, 1)
        XCTAssertEqual(store.memos.first?.transcript, "once")
        store.delete(memo.id)
        let reloaded = MemoStore(fileURL: url)
        XCTAssertTrue(reloaded.hasAccepted(memo.id))
        XCTAssertTrue(reloaded.ingestNote("late retry", id: memo.id))
        XCTAssertTrue(reloaded.memos.isEmpty)
    }

    @MainActor
    func testFailedDeleteDoesNotDropMemoOrCreateTombstone() throws {
        let url = try temporaryURL()
        let memo = Memo(source: .watchNote, status: .ready, transcript: "keep")
        try DurableState.save(MemoArchive(memos: [memo]), to: url)
        let store = MemoStore(fileURL: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        store.delete(memo.id)
        XCTAssertEqual(store.memos, [memo])
        XCTAssertNotNil(store.storageError)
    }
}
