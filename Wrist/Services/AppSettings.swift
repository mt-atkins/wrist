import Foundation
import Combine

/// Which model turns speech into text. Everything here runs on the iPhone.
enum TranscriptionEngine: Codable, Hashable, Sendable {
    case appleSpeech
    case whisper(variant: String)

    var id: String {
        switch self {
        case .appleSpeech: "apple-speech"
        case .whisper(let variant): "whisper:\(variant)"
        }
    }
}

/// Which model writes titles, summaries and to-dos (and answers Ask).
enum SummaryEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Apple Intelligence when available, otherwise local rules.
    case automatic
    case appleIntelligence
    case rules
    /// Bring your own model: Claude, OpenAI or any OpenAI-compatible server (Ollama, LM Studio…).
    case byom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .appleIntelligence: "Apple Intelligence"
        case .rules: "Local rules"
        case .byom: "Your own model"
        }
    }
}

enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openAI, openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: "Claude (Anthropic)"
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openAI: "https://api.openai.com/v1"
        case .openAICompatible: "http://192.168.1.10:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openAI: ""
        case .openAICompatible: "llama3.2"
        }
    }

    var keychainAccount: String { "byom.\(rawValue)" }
    var requiresKey: Bool { self != .openAICompatible }
}

/// A Sendable snapshot of the BYOM configuration, handed to background work.
struct RemoteModelConfig: Sendable, Equatable {
    var provider: ModelProvider
    var baseURL: String
    var model: String
    var apiKey: String?

    var displayName: String { "\(provider == .anthropic ? "Claude" : provider == .openAI ? "OpenAI" : "Custom") · \(model)" }
}

struct SummaryConfig: Sendable, Equatable {
    var engine: SummaryEngine
    var remote: RemoteModelConfig?
}

struct ObsidianSettings: Codable, Equatable {
    var enabled = false
    var vaultName = ""
    /// Folder inside the vault for capture notes.
    var folder = "Wrist"
    var linkInDailyNote = false
    /// Folder of daily notes inside the vault ("" = vault root). File names use `dailyFormat`.
    var dailyFolder = ""
    var dailyFormat = "yyyy-MM-dd"
}

/// User preferences. Secrets (API keys) live in the Keychain, never here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var transcription: TranscriptionEngine { didSet { save(transcription, "transcription") } }
    @Published var summary: SummaryEngine { didSet { save(summary, "summary") } }
    @Published var provider: ModelProvider { didSet { save(provider, "provider") } }
    @Published var baseURL: String { didSet { save(baseURL, "baseURL") } }
    @Published var model: String { didSet { save(model, "model") } }
    @Published var obsidian: ObsidianSettings { didSet { save(obsidian, "obsidian") } }
    @Published private(set) var freeAsksUsed: Int { didSet { save(freeAsksUsed, "freeAsksUsed") } }

    static let freeAskLimit = 3

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = defaults.data(forKey: "settings.\(key)"),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        transcription = load("transcription", .appleSpeech)
        summary = load("summary", .automatic)
        let provider = load("provider", ModelProvider.anthropic)
        self.provider = provider
        baseURL = load("baseURL", provider.defaultBaseURL)
        model = load("model", provider.defaultModel)
        obsidian = load("obsidian", ObsidianSettings())
        freeAsksUsed = load("freeAsksUsed", 0)
    }

    func selectProvider(_ next: ModelProvider) {
        provider = next
        baseURL = next.defaultBaseURL
        model = next.defaultModel
    }

    var apiKey: String? {
        get { Keychain.read(provider.keychainAccount) }
        set {
            if let newValue, !newValue.isEmpty { Keychain.write(newValue, account: provider.keychainAccount) }
            else { Keychain.delete(provider.keychainAccount) }
            objectWillChange.send()
        }
    }

    var remoteConfig: RemoteModelConfig {
        RemoteModelConfig(provider: provider, baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                          model: model.trimmingCharacters(in: .whitespaces), apiKey: apiKey)
    }

    /// What the pipeline should use right now. Pro-only engines fall back when Pro is off.
    func summaryConfig(isPro: Bool) -> SummaryConfig {
        if summary == .byom {
            return isPro ? SummaryConfig(engine: .byom, remote: remoteConfig) : SummaryConfig(engine: .automatic)
        }
        return SummaryConfig(engine: summary)
    }

    func transcriptionEngine(isPro: Bool) -> TranscriptionEngine {
        if case .whisper = transcription, !isPro { return .appleSpeech }
        return transcription
    }

    var freeAsksRemaining: Int { max(0, Self.freeAskLimit - freeAsksUsed) }

    func recordFreeAsk() { freeAsksUsed += 1 }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "settings.\(key)")
        }
    }
}
