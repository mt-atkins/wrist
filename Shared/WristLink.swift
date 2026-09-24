import Foundation

/// Keys and message kinds shared by the watch and phone halves of WatchConnectivity.
enum WristLink {
    static let kind = "kind"
    static let memoID = "memoID"
    static let createdAt = "createdAt"
    static let duration = "duration"
    static let text = "text"
    static let question = "question"
    static let answer = "answer"
    static let memos = "memos"
    static let actionID = "actionID"
    static let isDone = "isDone"

    enum Kind: String {
        case audio, note, ask, toggleAction
    }

    static func encode(_ memos: [Memo]) -> Data? {
        try? JSONEncoder().encode(memos)
    }

    static func decodeMemos(_ context: [String: Any]) -> [Memo]? {
        guard let data = context[memos] as? Data else { return nil }
        return try? JSONDecoder().decode([Memo].self, from: data)
    }
}
