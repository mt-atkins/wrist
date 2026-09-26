import XCTest
@testable import Wrist

final class HeuristicsTests: XCTestCase {
    func testExtractsActionItems() {
        let insight = Heuristics.insight(from: SampleData.transcript)
        XCTAssertTrue(insight.actionItems.contains { $0.hasPrefix("Send her the updated pricing deck") })
        XCTAssertTrue(insight.actionItems.contains { $0.hasPrefix("Book the photographer") })
    }

    func testTitleIsShortAndCapitalized() {
        let title = Heuristics.title(from: "okay so the plan for tomorrow is simple, really simple")
        XCTAssertEqual(title, "Okay so the plan for tomorrow")
    }

    func testTagsNeedRepeats() {
        XCTAssertEqual(Heuristics.tags(in: "launch launch pricing"), ["launch"])
    }

    func testAnswerFindsMatchingMemo() {
        var memo = Memo(source: .sample, transcript: SampleData.transcript)
        memo.title = "Launch coffee with Priya"
        let answer = Heuristics.answer("What did Priya say about the beta?", memos: [memo])
        XCTAssertTrue(answer.contains("Launch coffee with Priya"))
    }

    func testRetrievalFindsOldRelevantCaptureAheadOfRecentNoise() {
        var old = Memo(source: .sample, transcript: "Priya approved the beta launch.")
        old.createdAt = Date(timeIntervalSince1970: 1)
        let recent = (0..<30).map { _ in Memo(source: .sample, transcript: "Buy apples and bread.") }
        XCTAssertEqual(Heuristics.relevantMemos(for: "Priya beta", memos: recent + [old]).first?.id, old.id)
    }

    func testShortNamesMatchWholeTokensNotSubstrings() {
        let annual = Memo(source: .sample, transcript: "The annual report is ready.")
        let ann = Memo(source: .sample, transcript: "Ann approved the report.")
        XCTAssertEqual(Heuristics.relevantMemos(for: "What did Ann say?", memos: [annual, ann]).map(\.id), [ann.id])
    }

    func testFallbackQuotesTranscriptNotInventedSummary() {
        var memo = Memo(source: .sample, transcript: "Priya has not confirmed a date.")
        memo.summary = "Priya confirmed Friday."
        let answer = Heuristics.answer("Priya", memos: [memo])
        XCTAssertTrue(answer.contains("not an AI answer"))
        XCTAssertTrue(answer.contains(memo.transcript))
        XCTAssertFalse(answer.contains("Friday"))
    }

    func testExcerptRetrievesMatchBeyondTranscriptPrefix() {
        let transcript = String(repeating: "Unrelated discussion. ", count: 200) + "Zebra delivery is Thursday."
        XCTAssertTrue(Heuristics.excerpt(for: "Zebra", transcript: transcript).contains("Zebra delivery is Thursday."))
    }

    func testNoMatchAndWhitespaceDoNotInventAnAnswer() {
        let memo = Memo(source: .sample, transcript: "Buy bread.")
        XCTAssertTrue(Heuristics.relevantMemos(for: "   ", memos: [memo]).isEmpty)
        XCTAssertTrue(Heuristics.answer("Saturn", memos: [memo]).contains("couldn't find a matching capture"))
        XCTAssertEqual(Heuristics.insight(from: " \n ").source, .silent)
    }

    func testActionCuesRespectBoundariesAndNegation() {
        XCTAssertTrue(Heuristics.actionItems(in: ["The mustard looks great."]).isEmpty)
        XCTAssertTrue(Heuristics.actionItems(in: ["I don't need to book the hotel."]).isEmpty)
        XCTAssertEqual(Heuristics.actionItems(in: ["İpek: I need to book the hotel."]), ["Book the hotel"])
    }

    func testFallbackProvenanceIsPerResult() {
        XCTAssertEqual(Heuristics.insight(from: "Buy some bread.").source, .heuristic)
    }

    func testEmptyTranscriptIsSilent() async {
        let insight = await Summarizer.summarize("   ")
        XCTAssertEqual(insight.title, "Silent capture")
    }
}
