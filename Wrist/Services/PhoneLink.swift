import Foundation
import Combine
import WatchConnectivity

/// Phone side of WatchConnectivity: receives audio/notes/questions from the watch.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    static let shared = PhoneLink()

    @Published private(set) var lastError: String?
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
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            var digests = Array(memos.prefix(20)).map(\.digest)
            // Application context has a tight size budget. Keep the newest entries
            // rather than permanently failing all subsequent syncs on a large inbox.
            var data = try JSONEncoder().encode(digests)
            while data.count > 60_000 && !digests.isEmpty {
                digests.removeLast()
                data = try JSONEncoder().encode(digests)
            }
            try session.updateApplicationContext([WristLink.memos: data, WristLink.isPro: ProStore.shared.isPro])
            if digests.count < min(memos.count, 20) {
                lastError = "Some captures are too large for the watch inbox; they remain on iPhone."
            }
        } catch { lastError = "Watch sync failed: \(error.localizedDescription)" }
    }

    private func acknowledge(_ id: UUID) {
        guard let session, session.activationState == .activated else { return }
        // Queued ACK can be lost on reinstall; the watch retries and deduplication re-ACKs.
        session.transferUserInfo([WristLink.kind: WristLink.Kind.saved.rawValue, WristLink.memoID: id.uuidString])
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
            if let error { self.lastError = error.localizedDescription }
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
        Task { @MainActor in
            self.refreshState()
            self.pushDigest(MemoStore.shared.memos)
        }
    }

    /// Audio from the watch. The file is deleted when this returns, so move it synchronously.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let meta = file.metadata ?? [:]
        guard meta[WristLink.kind] as? String == WristLink.Kind.audio.rawValue else { return }
        guard let id = (meta[WristLink.memoID] as? String).flatMap(UUID.init) else { return }
        let createdAt = (meta[WristLink.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let duration = (meta[WristLink.duration] as? TimeInterval) ?? 0

        // WC removes its temporary file on return. Use a unique staging path so
        // duplicate callbacks cannot overwrite an audio file currently being read.
        let staging = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("incoming-\(UUID().uuidString).m4a")
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: staging)
        } catch {
            Task { @MainActor in self.lastError = "Audio reception failed: \(error.localizedDescription)" }
            return
        }
        Task { @MainActor in
            let store = MemoStore.shared
            do {
                if store.hasAccepted(id) {
                    try FileManager.default.removeItem(at: staging)
                    self.acknowledge(id)
                    return
                }
                let destination = store.audioURL(for: staging.lastPathComponent)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: staging, to: destination)
                if store.ingestAudio(at: destination, id: id, createdAt: createdAt, duration: duration, source: .watch) {
                    self.acknowledge(id)
                } else {
                    self.lastError = store.storageError
                    // No ACK: watch retains the original and retries.
                    try FileManager.default.removeItem(at: destination)
                }
            } catch { self.lastError = error.localizedDescription }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let kind = (userInfo[WristLink.kind] as? String).flatMap(WristLink.Kind.init)
        let memoID = (userInfo[WristLink.memoID] as? String).flatMap(UUID.init)
        switch kind {
        case .note:
            guard let memoID, let text = userInfo[WristLink.text] as? String else { return }
            let createdAt = (userInfo[WristLink.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
            Task { @MainActor in
                if MemoStore.shared.ingestNote(text, id: memoID, createdAt: createdAt) {
                    self.acknowledge(memoID)
                } else { self.lastError = MemoStore.shared.storageError }
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
        if message[WristLink.kind] as? String == WristLink.Kind.note.rawValue,
           let raw = message[WristLink.memoID] as? String, let id = UUID(uuidString: raw),
           let text = message[WristLink.text] as? String {
            let date = (message[WristLink.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
            Task { @MainActor in
                if MemoStore.shared.ingestNote(text, id: id, createdAt: date) {
                    replyHandler([WristLink.kind: WristLink.Kind.saved.rawValue, WristLink.memoID: id.uuidString])
                } else { replyHandler([:]) }
            }
            return
        }
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
