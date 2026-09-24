import Foundation

struct Insight: Equatable {
    var title: String
    var summary: String
    var actionItems: [String]
    var tags: [String]
}

/// Dependency-free fallback "AI" used when Apple Intelligence isn't available.
enum Heuristics {
    static let actionCues = [
        "need to", "needs to", "have to", "has to", "got to", "gotta", "must", "should",
        "remember to", "remind me to", "don't forget to", "make sure to", "to do", "todo",
        "i'll", "i will", "let's", "going to",
    ]

    static let stopwords: Set<String> = [
        "about", "after", "again", "also", "because", "been", "before", "being", "could", "doing",
        "going", "gonna", "have", "just", "know", "like", "make", "maybe", "might", "need", "really",
        "should", "some", "something", "that", "their", "them", "then", "there", "these", "thing",
        "think", "this", "those", "want", "were", "what", "when", "where", "which", "while", "with",
        "would", "your", "remember", "remind", "forget", "today", "tomorrow", "okay", "yeah",
    ]

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                result.append(s)
            }
        }
        return result.isEmpty ? [text] : result
    }

    static func insight(from text: String) -> Insight {
        let all = sentences(in: text)
        return Insight(
            title: title(from: all.first ?? text),
            summary: all.prefix(2).joined(separator: " "),
            actionItems: actionItems(in: all),
            tags: tags(in: text)
        )
    }

    static func title(from sentence: String) -> String {
        let words = sentence
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let title = words.prefix(6).joined(separator: " ")
        guard let first = title.first else { return "New capture" }
        return first.uppercased() + title.dropFirst()
    }

    static func actionItems(in sentences: [String]) -> [String] {
        sentences.compactMap { sentence in
            let lower = sentence.lowercased()
            // Use whichever cue appears earliest (longest wins a tie, e.g. "remind me to" over "to do").
            let matches = actionCues.compactMap { cue in lower.range(of: cue).map { (cue, $0) } }
            guard let range = matches.min(by: {
                $0.1.lowerBound == $1.1.lowerBound ? $0.0.count > $1.0.count : $0.1.lowerBound < $1.1.lowerBound
            })?.1 else { return nil }
            var action = String(sentence[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if action.lowercased().hasPrefix("to ") { action = String(action.dropFirst(3)) }
            guard action.split(separator: " ").count >= 2, let first = action.first else { return nil }
            return first.uppercased() + action.dropFirst()
        }
        .prefix(8)
        .map { $0 }
    }

    static func tags(in text: String) -> [String] {
        var counts: [String: Int] = [:]
        for raw in text.lowercased().components(separatedBy: CharacterSet.letters.inverted) where raw.count > 4 {
            if !stopwords.contains(raw) { counts[raw, default: 0] += 1 }
        }
        return counts
            .filter { $0.value > 1 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3)
            .map(\.key)
    }

    /// Keyword search: returns the capture that best matches the question.
    static func answer(_ question: String, memos: [Memo]) -> String {
        let keywords = Set(question.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 3 && !stopwords.contains($0) })
        let scored = memos.map { memo -> (Memo, Int) in
            let haystack = (memo.title + " " + memo.transcript).lowercased()
            return (memo, keywords.filter { haystack.contains($0) }.count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return "I couldn't find that in your captures."
        }
        let memo = best.0
        let detail = memo.summary.isEmpty ? String(memo.transcript.prefix(200)) : memo.summary
        return "From “\(memo.displayTitle)”: \(detail)"
    }
}
