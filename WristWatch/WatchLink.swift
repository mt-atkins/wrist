import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity: ships audio + notes to the phone, receives processed memos back.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    @Published private(set) var memos: [Memo] = []
    @Published private(set) var isReachable = false
    @Published private(set) var pendingTransfers = 0

    private let session = WCSession.default
    private let cacheKey = "memoDigest"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([Memo].self, from: data) {
            memos = cached
        }
        session.delegate = self
        session.activate()
    }

    func send(_ recording: AudioRecorder.Recording) {
        let metadata: [String: Any] = [
            WristLink.kind: WristLink.Kind.audio.rawValue,
            WristLink.memoID: UUID().uuidString,
            WristLink.createdAt: recording.startedAt.timeIntervalSince1970,
            WristLink.duration: recording.duration,
        ]
        session.transferFile(recording.url, metadata: metadata)
        pendingTransfers = session.outstandingFileTransfers.count
    }

    func sendNote(_ text: String) {
        session.transferUserInfo([
            WristLink.kind: WristLink.Kind.note.rawValue,
            WristLink.memoID: UUID().uuidString,
            WristLink.createdAt: Date().timeIntervalSince1970,
            WristLink.text: text,
        ])
    }

    func setAction(_ actionID: UUID, in memoID: UUID, done: Bool) {
        if let m = memos.firstIndex(where: { $0.id == memoID }),
           let a = memos[m].actionItems.firstIndex(where: { $0.id == actionID }) {
            memos[m].actionItems[a].isDone = done
            cache()
        }
        session.transferUserInfo([
            WristLink.kind: WristLink.Kind.toggleAction.rawValue,
            WristLink.memoID: memoID.uuidString,
            WristLink.actionID: actionID.uuidString,
            WristLink.isDone: done,
        ])
    }

    /// Ask the phone a question about your memos. The phone runs the on-device model and replies.
    func ask(_ question: String) async throws -> String {
        guard session.isReachable else { throw LinkError.unreachable }
        let message: [String: Any] = [WristLink.kind: WristLink.Kind.ask.rawValue, WristLink.question: question]
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume(returning: reply[WristLink.answer] as? String ?? "No answer.")
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    private func apply(_ incoming: [Memo]) {
        memos = incoming
        cache()
    }

    private func cache() {
        if let data = WristLink.encode(memos) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func refreshState() {
        isReachable = session.isReachable
        pendingTransfers = session.outstandingFileTransfers.count
    }

    enum LinkError: LocalizedError {
        case unreachable
        var errorDescription: String? { "Your iPhone isn't reachable right now." }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let memos = WristLink.decodeMemos(session.receivedApplicationContext)
        Task { @MainActor in
            if let memos { self.apply(memos) }
            self.refreshState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let memos = WristLink.decodeMemos(applicationContext) else { return }
        Task { @MainActor in self.apply(memos) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
        Task { @MainActor in self.refreshState() }
    }
}
