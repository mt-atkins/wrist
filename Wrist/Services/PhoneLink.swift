import Foundation
import WatchConnectivity

/// Phone side of WatchConnectivity: receives audio/notes/questions from the watch.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    static let shared = PhoneLink()

    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchAppInstalled = false

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Mirror the latest captures (without transcripts/audio) onto the watch.
    func pushDigest(_ memos: [Memo]) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = WristLink.encode(Array(memos.prefix(20)).map(\.digest)) else { return }
        try? session.updateApplicationContext([WristLink.memos: data])
    }

    private func refreshState() {
        guard let session else { return }
        isWatchPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshState()
            self.pushDigest(MemoStore.shared.memos)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch can connect.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    /// Audio from the watch. The file is deleted when this returns, so move it synchronously.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let meta = file.metadata ?? [:]
        guard meta[WristLink.kind] as? String == WristLink.Kind.audio.rawValue else { return }
        let id = (meta[WristLink.memoID] as? String).flatMap(UUID.init) ?? UUID()
        let createdAt = (meta[WristLink.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let duration = meta[WristLink.duration] as? TimeInterval ?? 0

        let destination = AudioRecorder.directory.appendingPathComponent("\(id.uuidString).m4a")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor in
            MemoStore.shared.ingestAudio(at: destination, id: id, createdAt: createdAt, duration: duration, source: .watch)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let kind = (userInfo[WristLink.kind] as? String).flatMap(WristLink.Kind.init)
        let memoID = (userInfo[WristLink.memoID] as? String).flatMap(UUID.init)
        switch kind {
        case .note:
            guard let text = userInfo[WristLink.text] as? String else { return }
            let createdAt = (userInfo[WristLink.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
            Task { @MainActor in
                MemoStore.shared.ingestNote(text, id: memoID ?? UUID(), createdAt: createdAt)
            }
        case .toggleAction:
            guard let memoID,
                  let actionID = (userInfo[WristLink.actionID] as? String).flatMap(UUID.init),
                  let done = userInfo[WristLink.isDone] as? Bool else { return }
            Task { @MainActor in
                MemoStore.shared.setAction(actionID, in: memoID, done: done)
            }
        default:
            break
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WristLink.kind] as? String == WristLink.Kind.ask.rawValue,
              let question = message[WristLink.question] as? String else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            let answer = await MemoStore.shared.ask(question)
            replyHandler([WristLink.answer: answer])
        }
    }
}
