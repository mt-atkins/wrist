import Foundation
import Combine

/// All mutations and pipeline completions serialize on the main actor. A capture is
/// accepted only after its archive is durable; processing success is not a delivery ACK.
@MainActor
final class MemoStore: ObservableObject {
    static let shared = MemoStore()
    @Published private(set) var memos: [Memo] = []
    @Published private(set) var storageError: String?
    private var deletedIDs: Set<UUID> = []
    private var canWrite = true
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let fileURL: URL

    init(fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("memos.json")) {
        self.fileURL = fileURL
        do {
            let archive = try DurableState.load(MemoArchive.self, from: fileURL) ?? MemoArchive()
            memos = archive.memos
            deletedIDs = archive.deletedIDs
            for memo in memos where memo.status.isWorking { process(memo.id) }
        } catch {
            canWrite = false
            storageError = "Cannot read captures. Original data has been preserved: \(error.localizedDescription)"
        }
    }

    /// Includes tombstones: late transport retries must never resurrect a deletion.
    func hasAccepted(_ id: UUID) -> Bool {
        memos.contains { $0.id == id } || deletedIDs.contains(id)
    }

    @discardableResult
    func ingestAudio(at url: URL, id: UUID = UUID(), createdAt: Date, duration: TimeInterval, source: MemoSource) -> Bool {
        if hasAccepted(id) { return true }
        return insert(Memo(id: id, createdAt: createdAt, duration: duration, audioFileName: url.lastPathComponent, source: source))
    }

    @discardableResult
    func ingestNote(_ text: String, id: UUID = UUID(), createdAt: Date = Date(), source: MemoSource = .watchNote) -> Bool {
        if hasAccepted(id) { return true }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return insert(Memo(id: id, createdAt: createdAt, source: source, transcript: text))
    }

    private func insert(_ memo: Memo) -> Bool {
        guard commit([memo] + memos, deleted: deletedIDs) else { return false }
        process(memo.id)
        return true
    }

    func addSample() {
        _ = insert(Memo(duration: 48, source: .sample, transcript: SampleData.transcript))
    }

    func process(_ id: UUID) {
        guard canWrite, tasks[id] == nil, memo(id) != nil else { return }
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks[id] = nil }
            do {
                if let memo = self.memo(id), let file = memo.audioFileName, memo.transcript.isEmpty {
                    guard self.update(id, { $0.status = .transcribing }) else { return }
                    let text = try await Transcriber.transcribe(url: self.audioURL(for: file))
                    try Task.checkCancellation()
                    guard self.update(id, { $0.transcript = text }) else { return }
                }
                guard let memo = self.memo(id), self.update(id, { $0.status = .thinking }) else { return }
                let insight = await Summarizer.summarize(memo.transcript)
                try Task.checkCancellation()
                self.update(id) {
                    $0.title = insight.title
                    $0.summary = insight.summary
                    $0.insightSource = insight.source
                    let previous = $0.actionItems
                    $0.actionItems = insight.actionItems.map { title in
                        previous.first { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? ActionItem(text: title)
                    }
                    $0.tags = insight.tags
                    $0.errorMessage = nil
                    $0.status = .ready
                }
            } catch is CancellationError {
                // Deletion cancels work; never write a late result back.
            } catch {
                guard !Task.isCancelled else { return }
                self.update(id) {
                    $0.status = .failed
                    $0.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func memo(_ id: UUID) -> Memo? { memos.first { $0.id == id } }

    @discardableResult
    func update(_ id: UUID, _ change: (inout Memo) -> Void) -> Bool {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return false }
        var next = memos
        change(&next[index])
        return commit(next, deleted: deletedIDs)
    }

    func setAction(_ actionID: UUID, in memoID: UUID, done: Bool) {
        update(memoID) { memo in
            if let i = memo.actionItems.firstIndex(where: { $0.id == actionID }) {
                memo.actionItems[i].isDone = done
            }
        }
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        let file = memo(id)?.audioFileName
        var deleted = deletedIDs
        deleted.insert(id)
        guard commit(memos.filter { $0.id != id }, deleted: deleted) else { return false }
        tasks[id]?.cancel()
        if let file {
            do { try FileManager.default.removeItem(at: audioURL(for: file)) }
            catch { storageError = "Capture deleted, but audio cleanup failed: \(error.localizedDescription)" }
        }
        return true
    }

    func audioURL(for fileName: String) -> URL {
        AudioRecorder.directory.appendingPathComponent(fileName)
    }

    func ask(_ question: String) async -> String {
        await Summarizer.answer(question, from: memos)
    }

    private func commit(_ next: [Memo], deleted: Set<UUID>) -> Bool {
        guard canWrite else { return false }
        do {
            try DurableState.save(MemoArchive(memos: next, deletedIDs: deleted), to: fileURL)
            memos = next
            deletedIDs = deleted
            storageError = nil
            PhoneLink.shared.pushDigest(memos)
            return true
        } catch {
            storageError = "Captures could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
