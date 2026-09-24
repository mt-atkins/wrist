import Foundation

/// A single thing you captured from your wrist (or phone), plus what the AI made of it.
struct Memo: Identifiable, Codable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var duration: TimeInterval = 0
    var audioFileName: String?
    var source: MemoSource
    var status: MemoStatus = .queued
    var transcript = ""
    var title = ""
    var summary = ""
    var actionItems: [ActionItem] = []
    var tags: [String] = []
    var errorMessage: String?

    var displayTitle: String { title.isEmpty ? "New capture" : title }
    var openActionCount: Int { actionItems.filter { !$0.isDone }.count }

    /// A lightweight copy for syncing to the watch (application context is capped at ~64 KB).
    var digest: Memo {
        var copy = self
        copy.transcript = ""
        copy.audioFileName = nil
        return copy
    }
}

struct ActionItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var isDone = false
}

enum MemoSource: String, Codable {
    case watch, watchNote, phone, sample

    var symbol: String {
        switch self {
        case .watch: "applewatch"
        case .watchNote: "text.bubble"
        case .phone: "iphone"
        case .sample: "sparkles"
        }
    }
}

enum MemoStatus: String, Codable {
    case queued, transcribing, thinking, ready, failed

    var label: String {
        switch self {
        case .queued: "Waiting"
        case .transcribing: "Transcribing"
        case .thinking: "Thinking"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    var isWorking: Bool { self == .queued || self == .transcribing || self == .thinking }
}
