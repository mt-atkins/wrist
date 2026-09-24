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

    func testEmptyTranscriptIsSilent() async {
        let insight = await Summarizer.summarize("   ")
        XCTAssertEqual(insight.title, "Silent capture")
    }
}
