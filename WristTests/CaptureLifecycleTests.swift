import XCTest
@testable import Wrist

final class CaptureLifecycleTests: XCTestCase {
    @MainActor
    func testFailedHandoffRetainsRecordingUntilConsumed() {
        let recorder = AudioRecorder()
        let recording = AudioRecorder.Recording(url: URL(fileURLWithPath: "/tmp/wrist-test.m4a"), duration: 4, startedAt: Date())
        recorder.retainForRetry(recording)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.pendingRecording?.url, recording.url)
        XCTAssertEqual(recorder.stop()?.url, recording.url)
        XCTAssertNil(recorder.pendingRecording)
        XCTAssertNil(recorder.stop(), "A retained capture is consumed once")
    }

    @MainActor
    func testBlankNoteIsNotPersisted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("memos.json")
        let store = MemoStore(fileURL: file)
        XCTAssertFalse(store.ingestNote(" \n ", source: .phone))
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testResultProvenanceSurvivesSerialization() throws {
        var memo = Memo(source: .phone, transcript: "Remember to buy milk")
        memo.insightSource = .heuristic
        let decoded = try JSONDecoder().decode(Memo.self, from: JSONEncoder().encode(memo))
        XCTAssertEqual(decoded.insightSource, .heuristic)
    }

    func testOlderMemoWithoutProvenanceStillDecodes() throws {
        let memo = Memo(source: .phone, transcript: "Old capture")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(memo)) as? [String: Any])
        object.removeValue(forKey: "insightSource")
        let decoded = try JSONDecoder().decode(Memo.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.transcript, "Old capture")
        XCTAssertNil(decoded.insightSource)
    }
}
