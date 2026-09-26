import Foundation
import Combine
import WatchConnectivity

/// Watch side of WatchConnectivity: ships audio + notes to the phone, receives processed memos back.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    @Published private(set) var memos: [Memo] = []
    @Published private(set) var isReachable = false
    @Published private(set) var pendingTransfers = 0
    /// Mirrored from the iPhone; gates Shortcuts/Action-button capture.
    @Published private(set) var isPro = UserDefaults.standard.bool(forKey: "isPro")

    @Published private(set) var lastError: String?
    @Published private(set) var lastDeliveredID: UUID?
    private var outbox: [PendingCapture] = []
    private var outboxWritable = true
    private var lastAttempt: [UUID: Date] = [:]
    private var retryTask: Task<Void, Never>?
    private let outboxURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pending-captures.json")
    private let session = WCSession.default
    private let cacheKey = "memoDigest"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            do { memos = try JSONDecoder().decode([Memo].self, from: data) }
            catch { lastError = "Inbox cache is unreadable; waiting for iPhone sync: \(error.localizedDescription)" }
        }
        do {
            outbox = try DurableState.load([PendingCapture].self, from: outboxURL) ?? []
            pendingTransfers = outbox.count
        } catch {
            outboxWritable = false
            lastError = "Cannot read pending captures; original data preserved: \(error.localizedDescription)"
        }
        session.delegate = self
        session.activate()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.retryPending()
            }
        }
    }

    deinit { retryTask?.cancel() }

    /// True means durably queued locally, NOT delivered to the phone.
    @discardableResult
    func send(_ recording: AudioRecorder.Recording) -> Bool {
        // The recorder writes into Documents/Recordings; keep that original until
        // an application-level ACK, never just a WC transport completion.
        if outbox.contains(where: { $0.audioFileName == recording.url.lastPathComponent }) { return true }
        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            lastError = "The recording file is missing."
            return false
        }
        let item = PendingCapture(id: UUID(), createdAt: recording.startedAt,
                                  duration: recording.duration, audioFileName: recording.url.lastPathComponent)
        return enqueue(item)
    }

    @discardableResult
    func sendNote(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return enqueue(PendingCapture(id: UUID(), createdAt: Date(), duration: 0, text: text))
    }

    private func enqueue(_ item: PendingCapture) -> Bool {
        guard persistOutbox(outbox + [item]) else { return false }
        retryPending()
        return true
    }

    private func persistOutbox(_ next: [PendingCapture]) -> Bool {
        guard outboxWritable else { return false }
        do {
            try DurableState.save(next, to: outboxURL)
            outbox = next
            pendingTransfers = next.count // awaiting phone save, including notes
            lastError = nil
            return true
        } catch {
            lastError = "Could not save pending captures: \(error.localizedDescription)"
            return false
        }
    }

    /// WC queues survive disconnects; replay only if no transport is outstanding.
    /// Missing ACKs are retried on launch, activation, reachability and while awake.
    func retryPending() {
        guard outboxWritable, session.activationState == .activated else { return }
        let files = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?[WristLink.memoID] as? String })
        let notes = Set(session.outstandingUserInfoTransfers.compactMap { $0.userInfo[WristLink.memoID] as? String })
        for item in outbox {
            // Foreground fast path also runs when an OS background transfer is pending.
            if item.audioFileName == nil, session.isReachable {
                session.sendMessage(item.metadata, replyHandler: { reply in
                    guard reply[WristLink.kind] as? String == WristLink.Kind.saved.rawValue,
                          reply[WristLink.memoID] as? String == item.id.uuidString else { return }
                    Task { @MainActor in self.acknowledge(item.id) }
                }, errorHandler: { _ in /* durable WC queue will retry */ })
            }
            guard !files.contains(item.id.uuidString), !notes.contains(item.id.uuidString),
                  Date().timeIntervalSince(lastAttempt[item.id] ?? .distantPast) >= 60 else { continue }
            lastAttempt[item.id] = Date()
            if let name = item.audioFileName {
                let url = AudioRecorder.directory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    lastError = "Pending capture audio is missing; the capture remains queued."
                    continue
                }
                session.transferFile(url, metadata: item.metadata)
            } else {
                session.transferUserInfo(item.metadata)
            }
        }
    }

    private func acknowledge(_ id: UUID) {
        guard let item = outbox.first(where: { $0.id == id }) else { return }
        // If this write fails retain both the entry and file and retry safely.
        guard persistOutbox(outbox.filter { $0.id != id }) else { return }
        lastAttempt[id] = nil
        lastDeliveredID = id
        if let name = item.audioFileName {
            do { try FileManager.default.removeItem(at: AudioRecorder.directory.appendingPathComponent(name)) }
            catch { lastError = "Delivered, but audio cleanup failed: \(error.localizedDescription)" }
        }
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
                continuation.resume(returning: (reply[WristLink.answer] as? String) ?? "No answer.")
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    private func apply(_ incoming: [Memo]) {
        memos = incoming
        cache()
    }

    private func applyPro(_ value: Bool?) {
        guard let value else { return }
        isPro = value
        UserDefaults.standard.set(value, forKey: "isPro")
    }

    private func cache() {
        do {
            let data = try JSONEncoder().encode(memos)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch { lastError = "Could not cache the inbox: \(error.localizedDescription)" }
    }

    private func refreshState() {
        isReachable = session.isReachable
        pendingTransfers = outbox.count
        retryPending()
    }

    enum LinkError: LocalizedError {
        case unreachable
        var errorDescription: String? { "Your iPhone isn't reachable right now." }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let memos = WristLink.decodeMemos(session.receivedApplicationContext)
        let isPro = session.receivedApplicationContext[WristLink.isPro] as? Bool
        Task { @MainActor in
            if let error { self.lastError = error.localizedDescription }
            if let memos { self.apply(memos) }
            self.applyPro(isPro)
            self.refreshState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let isPro = applicationContext[WristLink.isPro] as? Bool
        let memos = WristLink.decodeMemos(applicationContext)
        Task { @MainActor in
            if let memos { self.apply(memos) }
            self.applyPro(isPro)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo[WristLink.kind] as? String == WristLink.Kind.saved.rawValue,
              let raw = userInfo[WristLink.memoID] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.acknowledge(id) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            if let error { self.lastError = "Transfer will retry: \(error.localizedDescription)" }
            self.refreshState()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Transport completion is not evidence that MemoStore saved the capture.
        Task { @MainActor in
            if let error { self.lastError = "Transfer will retry: \(error.localizedDescription)" }
            self.refreshState()
        }
    }
}
