import Foundation
import Combine
import WhisperKit

/// A downloadable on-device Whisper model, shown in the Handy-style picker.
struct WhisperModel: Identifiable, Hashable, Sendable {
    /// Folder name in argmaxinc/whisperkit-coreml.
    let variant: String
    let name: String
    let size: String
    /// 1–5, for the little speed/accuracy meters.
    let speed: Int
    let accuracy: Int
    let note: String

    var id: String { variant }

    static let catalog: [WhisperModel] = [
        WhisperModel(variant: "openai_whisper-tiny", name: "Whisper Tiny", size: "≈75 MB",
                     speed: 5, accuracy: 2, note: "Instant, fine for quick notes"),
        WhisperModel(variant: "openai_whisper-base", name: "Whisper Base", size: "≈145 MB",
                     speed: 4, accuracy: 3, note: "Good all-rounder"),
        WhisperModel(variant: "openai_whisper-small", name: "Whisper Small", size: "≈480 MB",
                     speed: 3, accuracy: 4, note: "Better with accents and names"),
        WhisperModel(variant: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Whisper Large v3 Turbo", size: "≈630 MB",
                     speed: 2, accuracy: 5, note: "Best accuracy, needs a recent iPhone"),
    ]
}

/// Downloads, stores and deletes Whisper models. Models live in Application Support, excluded from backup.
@MainActor
final class WhisperModelStore: ObservableObject {
    static let shared = WhisperModelStore()

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    private var downloads: [String: Task<Void, Never>] = [:]

    nonisolated static var baseDirectory: URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// Container paths change across app updates, so find the model folder by name rather than storing a path.
    nonisolated static func folder(for variant: String) -> URL? {
        let enumerator = FileManager.default.enumerator(at: baseDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == variant,
               (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
                || ((try? FileManager.default.contentsOfDirectory(atPath: url.path))?.contains { $0.hasSuffix(".mlmodelc") } ?? false) {
                return url
            }
        }
        return nil
    }

    init() {
        for model in WhisperModel.catalog {
            states[model.variant] = Self.folder(for: model.variant) == nil ? .notDownloaded : .ready
        }
    }

    func state(of model: WhisperModel) -> State { states[model.variant] ?? .notDownloaded }

    func download(_ model: WhisperModel) {
        guard downloads[model.variant] == nil else { return }
        states[model.variant] = .downloading(0)
        downloads[model.variant] = Task { [weak self] in
            do {
                _ = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: Self.baseDirectory,
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in self?.states[model.variant] = .downloading(fraction) }
                    }
                )
                self?.states[model.variant] = .ready
            } catch is CancellationError {
                self?.states[model.variant] = .notDownloaded
            } catch {
                self?.states[model.variant] = .failed(error.localizedDescription)
            }
            self?.downloads[model.variant] = nil
        }
    }

    func cancel(_ model: WhisperModel) {
        downloads[model.variant]?.cancel()
    }

    func delete(_ model: WhisperModel) {
        if let folder = Self.folder(for: model.variant) {
            try? FileManager.default.removeItem(at: folder)
        }
        states[model.variant] = .notDownloaded
        Task { await WhisperTranscriber.shared.unload(model.variant) }
        if AppSettings.shared.transcription == .whisper(variant: model.variant) {
            AppSettings.shared.transcription = .appleSpeech
        }
    }
}

/// Runs a downloaded Whisper model entirely on device. Keeps the last model warm.
actor WhisperTranscriber {
    static let shared = WhisperTranscriber()

    enum Failure: LocalizedError {
        case notDownloaded(String)
        var errorDescription: String? {
            switch self {
            case .notDownloaded(let name): "\(name) isn't downloaded. Download it in Settings → Models, or switch back to Apple Speech."
            }
        }
    }

    private var loaded: (variant: String, pipe: WhisperKit)?

    func transcribe(url: URL, variant: String) async throws -> String {
        let pipe = try await pipeline(for: variant)
        let results = try await pipe.transcribe(audioPath: url.path)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload(_ variant: String) {
        if loaded?.variant == variant { loaded = nil }
    }

    private func pipeline(for variant: String) async throws -> WhisperKit {
        if let loaded, loaded.variant == variant { return loaded.pipe }
        guard let folder = WhisperModelStore.folder(for: variant) else {
            let name = WhisperModel.catalog.first { $0.variant == variant }?.name ?? variant
            throw Failure.notDownloaded(name)
        }
        loaded = nil // release the previous model's memory first
        let pipe = try await WhisperKit(WhisperKitConfig(model: variant, modelFolder: folder.path, download: false))
        loaded = (variant, pipe)
        return pipe
    }
}
