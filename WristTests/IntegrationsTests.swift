import XCTest
@testable import Wrist

final class IntegrationsTests: XCTestCase {
    private func sampleMemo() -> Memo {
        var memo = Memo(createdAt: Date(timeIntervalSince1970: 1_790_000_000), duration: 48, source: .watch,
                        status: .ready, transcript: "Remind me to book the photographer.")
        memo.title = "Launch: photos / beta?"
        memo.summary = "Book the photographer for launch shots."
        memo.actionItems = [ActionItem(text: "Book the photographer"), ActionItem(text: "Email Marcus", isDone: true)]
        memo.tags = ["launch"]
        memo.insightSource = .ownModel
        memo.insightModel = "Claude · claude-opus-5"
        return memo
    }

    func testObsidianNoteHasFrontmatterTasksAndTranscript() {
        let markdown = ObsidianExporter.markdown(for: sampleMemo())
        XCTAssertTrue(markdown.hasPrefix("---\nwrist-id: "))
        XCTAssertTrue(markdown.contains("tags: [wrist, launch]"))
        XCTAssertTrue(markdown.contains("summarized-by: Claude · claude-opus-5"), markdown)
        XCTAssertTrue(markdown.contains("- [ ] Book the photographer"))
        XCTAssertTrue(markdown.contains("- [x] Email Marcus"))
        XCTAssertTrue(markdown.contains("## Transcript\n\nRemind me to book the photographer."))
    }

    func testObsidianPathIsFilesystemSafe() {
        let path = ObsidianExporter.notePath(for: sampleMemo(), folder: "/Wrist/")
        XCTAssertTrue(path.hasPrefix("Wrist/"))
        XCTAssertTrue(path.hasSuffix(".md"))
        XCTAssertFalse(path.dropFirst("Wrist/".count).contains("/"))
        XCTAssertFalse(path.contains(":"))
        XCTAssertFalse(path.contains("?"))
    }

    func testRemoteJSONToleratesFencesAndChatter() {
        let reply = "Sure!\n```json\n{\"title\":\"Plants\",\"summary\":\"Water them.\",\"actionItems\":[\"Water the plants\"],\"tags\":[\"home\"]}\n```"
        let decoded = RemoteModel.decodeJSON(RemoteModel.Generated.self, from: reply)
        XCTAssertEqual(decoded?.title, "Plants")
        XCTAssertEqual(decoded?.actionItems, ["Water the plants"])
        XCTAssertNil(RemoteModel.decodeJSON(RemoteModel.Generated.self, from: "no json here"))
    }

    @MainActor
    func testProOnlyEnginesFallBackWithoutPro() {
        let defaults = UserDefaults(suiteName: "IntegrationsTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.summary = .byom
        settings.transcription = .whisper(variant: "openai_whisper-base")
        XCTAssertEqual(settings.summaryConfig(isPro: false).engine, .automatic)
        XCTAssertEqual(settings.summaryConfig(isPro: true).engine, .byom)
        XCTAssertEqual(settings.transcriptionEngine(isPro: false), .appleSpeech)
        XCTAssertEqual(settings.transcriptionEngine(isPro: true), .whisper(variant: "openai_whisper-base"))
    }

    @MainActor
    func testFreeAskAllowanceCountsDown() {
        let defaults = UserDefaults(suiteName: "IntegrationsTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.freeAsksRemaining, AppSettings.freeAskLimit)
        for _ in 0..<AppSettings.freeAskLimit + 1 { settings.recordFreeAsk() }
        XCTAssertEqual(settings.freeAsksRemaining, 0)
        XCTAssertEqual(AppSettings(defaults: defaults).freeAsksRemaining, 0, "Allowance persists across launches")
    }

    @MainActor
    func testRulesEngineNeverCallsRemote() async {
        let insight = await Summarizer.summarize("Remember to call Sam tomorrow.", config: SummaryConfig(engine: .rules))
        XCTAssertEqual(insight.source, .heuristic)
        let byomWithoutConfig = await Summarizer.summarize("Remember to call Sam.", config: SummaryConfig(engine: .byom, remote: nil))
        XCTAssertNotEqual(byomWithoutConfig.source, .ownModel)
    }
}
