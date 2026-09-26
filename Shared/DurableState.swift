import Foundation

/// Atomic replacement, with a strict distinction between missing and unreadable data.
/// Callers must disable writes after a load failure until the original is recovered.
enum DurableState {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

struct MemoArchive: Codable {
    var memos: [Memo] = []
    var deletedIDs: Set<UUID> = []

    init(memos: [Memo] = [], deletedIDs: Set<UUID> = []) {
        self.memos = memos
        self.deletedIDs = deletedIDs
    }

    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode([Memo].self) {
            memos = legacy
            deletedIDs = []
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            memos = try values.decode([Memo].self, forKey: .memos)
            deletedIDs = try values.decode(Set<UUID>.self, forKey: .deletedIDs)
        }
        var seen = Set<UUID>()
        memos = memos.filter { !deletedIDs.contains($0.id) && seen.insert($0.id).inserted }
    }
}

struct PendingCapture: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String?
    var text: String?

    var metadata: [String: Any] {
        var result: [String: Any] = [
            WristLink.kind: audioFileName == nil ? WristLink.Kind.note.rawValue : WristLink.Kind.audio.rawValue,
            WristLink.memoID: id.uuidString,
            WristLink.createdAt: createdAt.timeIntervalSince1970,
            WristLink.duration: duration
        ]
        if let text { result[WristLink.text] = text }
        return result
    }
}
