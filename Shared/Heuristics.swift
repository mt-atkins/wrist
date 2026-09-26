import Foundation

struct Insight: Equatable {
    var title: String
    var summary: String
    var actionItems: [String]
    var tags: [String]
    /// Per-result provenance, not just the device's current model availability.
    var source: InsightSource = .heuristic
}

enum InsightSource: String, Codable {
    case appleIntelligence, heuristic, silent
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
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Insight(title: "Silent capture", summary: "No speech was detected.", actionItems: [], tags: [], source: .silent)
        }
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
            // Conservative fallback: don't turn explicit negations into obligations.
            if ["don't need to", "do not need to", "don't have to", "do not have to", "should not", "shouldn't", "must not", "mustn't", "not going to"].contains(where: { lower.contains($0) }) { return nil }
            // Use whichever cue appears earliest (longest wins a tie, e.g. "remind me to" over "to do").
            let matches = actionCues.compactMap { cue -> (String, Range<String.Index>)? in
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: cue) + "(?![\\p{L}\\p{N}])"
                return sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]).map { (cue, $0) }
            }
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

    private static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }

    static func keywords(in question: String) -> Set<String> {
        tokens(question).subtracting(stopwords).subtracting([
            "a", "an", "the", "i", "me", "my", "we", "our", "you", "is", "it", "of", "on", "in",
            "to", "do", "did", "does", "was", "are", "and", "or", "for", "at", "be", "say", "said",
            "tell", "how", "any", "notes", "captures", "please", "can", "all", "from"
        ])
    }

    /// Rank the entire corpus before applying context limits. Exact tokens avoid Ann→annual.
    static func relevantMemos(for question: String, memos: [Memo], limit: Int = 8) -> [Memo] {
        let keywords = keywords(in: question)
        guard !keywords.isEmpty, limit > 0 else { return [] }
        return memos.filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { memo in (memo, keywords.intersection(tokens(memo.transcript)).count) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.createdAt != $1.0.createdAt { return $0.0.createdAt > $1.0.createdAt }
                return $0.0.id.uuidString < $1.0.id.uuidString
            }
            .prefix(limit).map { $0.0 }
    }

    /// A verbatim window around a match, not a generated summary that may contain mistakes.
    static func excerpt(for question: String, transcript: String, limit: Int = 900) -> String {
        guard limit > 0 else { return "" }
        let keywords = keywords(in: question)
        let ranges = keywords.compactMap { word in
            transcript.range(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])",
                             options: [.regularExpression, .caseInsensitive, .diacriticInsensitive])
        }
        let match = ranges.min { $0.lowerBound < $1.lowerBound }?.lowerBound ?? transcript.startIndex
        let start = transcript.index(match, offsetBy: -min(100, limit / 4), limitedBy: transcript.startIndex) ?? transcript.startIndex
        let end = transcript.index(start, offsetBy: limit, limitedBy: transcript.endIndex) ?? transcript.endIndex
        return (start > transcript.startIndex ? "…" : "") + String(transcript[start..<end]) + (end < transcript.endIndex ? "…" : "")
    }

    static func answer(_ question: String, memos: [Memo]) -> String {
        guard let memo = relevantMemos(for: question, memos: memos).first else {
            return "Keyword search (not an AI answer): I couldn't find a matching capture. Try a specific name or topic."
        }
        return "Keyword match (not an AI answer) from “\(memo.displayTitle)”: “\(excerpt(for: question, transcript: memo.transcript, limit: 350))”"
    }
}
