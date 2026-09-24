import Foundation

/// Source of truth for captures on the phone: persistence, the transcribe → summarize pipeline,
/// and syncing a digest back to the watch.
@MainActor
final class MemoStore: ObservableObject {
    static let shared = MemoStore()

    @Published private(set) var memos: [Memo] = []

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("memos.json")

    init() {
        load()
        // Anything interrupted mid-pipeline (app killed) gets picked back up.
        for memo in memos where memo.status.isWorking {
            process(memo.id)
        }
    }

    // MARK: Ingest

    func ingestAudio(at url: URL, id: UUID = UUID(), createdAt: Date, duration: TimeInterval, source: MemoSource) {
        guard !memos.contains(where: { $0.id == id }) else { return }
        let memo = Memo(id: id, createdAt: createdAt, duration: duration, audioFileName: url.lastPathComponent, source: source)
        memos.insert(memo, at: 0)
        save()
        process(id)
    }

    func ingestNote(_ text: String, id: UUID = UUID(), createdAt: Date = Date()) {
        guard !memos.contains(where: { $0.id == id }) else { return }
        let memo = Memo(id: id, createdAt: createdAt, source: .watchNote, transcript: text)
        memos.insert(memo, at: 0)
        save()
        process(id)
    }

    func addSample() {
        let memo = Memo(duration: 48, source: .sample, transcript: SampleData.transcript)
        memos.insert(memo, at: 0)
        save()
        process(memo.id)
    }

    // MARK: Pipeline

    func process(_ id: UUID) {
        Task {
            do {
                if let memo = memo(id), let file = memo.audioFileName, memo.transcript.isEmpty {
                    update(id) { $0.status = .transcribing }
                    let text = try await Transcriber.transcribe(url: audioURL(for: file))
                    update(id) { $0.transcript = text }
                }
                guard let memo = memo(id) else { return }
                update(id) { $0.status = .thinking }
                let insight = await Summarizer.summarize(memo.transcript)
                update(id) {
                    $0.title = insight.title
                    $0.summary = insight.summary
                    $0.actionItems = insight.actionItems.map { ActionItem(text: $0) }
                    $0.tags = insight.tags
                    $0.errorMessage = nil
                    $0.status = .ready
                }
            } catch {
                update(id) {
                    $0.status = .failed
                    $0.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Editing

    func memo(_ id: UUID) -> Memo? {
        memos.first { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout Memo) -> Void) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        change(&memos[index])
        save()
    }

    func setAction(_ actionID: UUID, in memoID: UUID, done: Bool) {
        update(memoID) { memo in
            if let i = memo.actionItems.firstIndex(where: { $0.id == actionID }) {
                memo.actionItems[i].isDone = done
            }
        }
    }

    func delete(_ id: UUID) {
        if let file = memo(id)?.audioFileName {
            try? FileManager.default.removeItem(at: audioURL(for: file))
        }
        memos.removeAll { $0.id == id }
        save()
    }

    func audioURL(for fileName: String) -> URL {
        AudioRecorder.directory.appendingPathComponent(fileName)
    }

    // MARK: Ask

    func ask(_ question: String) async -> String {
        await Summarizer.answer(question, from: memos)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Memo].self, from: data) else { return }
        memos = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memos) {
            try? data.write(to: fileURL, options: .atomic)
        }
        PhoneLink.shared.pushDigest(memos)
    }
}
