import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a transcript into a title, summary, to-dos and tags, and answers questions across memos.
/// Uses Apple's on-device Foundation Model when Apple Intelligence is available; otherwise
/// falls back to `Heuristics` so the app still works in the simulator and on older devices.
enum Summarizer {
    static var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func summarize(_ transcript: String) async -> Insight {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Insight(title: "Silent capture", summary: "No speech was detected.", actionItems: [], tags: [])
        }
        #if canImport(FoundationModels)
        if usesAppleIntelligence, let insight = try? await modelSummary(of: text) {
            return insight
        }
        #endif
        return Heuristics.insight(from: text)
    }

    static func answer(_ question: String, from memos: [Memo]) async -> String {
        let usable = memos.filter { !$0.transcript.isEmpty }
        guard !usable.isEmpty else { return "You haven't captured anything yet." }
        #if canImport(FoundationModels)
        if usesAppleIntelligence, let answer = try? await modelAnswer(question, memos: usable) {
            return answer
        }
        #endif
        return Heuristics.answer(question, memos: usable)
    }

    #if canImport(FoundationModels)
    @Generable
    struct GeneratedInsight {
        @Guide(description: "A short, specific title of 2 to 6 words, no quotes or trailing punctuation.")
        var title: String
        @Guide(description: "One to three sentences capturing the key point, written plainly.")
        var summary: String
        @Guide(description: "Concrete to-dos the speaker needs to do, each starting with a verb. Empty if there are none.")
        var actionItems: [String]
        @Guide(description: "One to three lowercase, single-word topic tags.")
        var tags: [String]
    }

    private static func modelSummary(of transcript: String) async throws -> Insight {
        let session = LanguageModelSession(instructions: """
            You turn raw voice captures recorded on an Apple Watch into crisp notes. \
            Stay faithful to what was said and never invent names, dates or facts.
            """)
        let response = try await session.respond(
            to: "Transcript:\n\(String(transcript.prefix(8_000)))",
            generating: GeneratedInsight.self
        )
        let g = response.content
        return Insight(
            title: g.title,
            summary: g.summary,
            actionItems: Array(g.actionItems.prefix(8)),
            tags: Array(g.tags.prefix(3)).map { $0.lowercased() }
        )
    }

    private static func modelAnswer(_ question: String, memos: [Memo]) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Keep the context inside the on-device model's window: newest first, ~6k chars.
        var context = ""
        for memo in memos {
            let entry = "[\(formatter.string(from: memo.createdAt))] \(memo.displayTitle)\n\(memo.transcript.prefix(1_500))\n\n"
            if context.count + entry.count > 6_000 { break }
            context += entry
        }

        let session = LanguageModelSession(instructions: """
            You are Wrist, a memory assistant. Answer the user's question using only the voice \
            captures provided. Be brief (at most three sentences) because the answer is read on a watch. \
            If the captures don't contain the answer, say so.
            """)
        let response = try await session.respond(to: "Captures:\n\(context)\nQuestion: \(question)")
        return response.content
    }
    #endif
}
