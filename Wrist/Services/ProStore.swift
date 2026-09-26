import Foundation
import Combine
import StoreKit

/// Wrist Pro: a one-time, non-consumable unlock. No subscription, no account.
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()
    static let productID = "com.distyll.wrist.pro"

    @Published private(set) var isPro = false
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private var updates: Task<Void, Never>?
    private let cacheKey = "pro.unlocked"

    init() {
        // Cached so the UI doesn't flash the paywall; StoreKit's verified entitlements win on refresh.
        isPro = UserDefaults.standard.bool(forKey: cacheKey)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    func load() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            lastError = "Couldn't reach the App Store: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                } else {
                    lastError = "The purchase couldn't be verified."
                }
                await refreshEntitlements()
            case .pending:
                lastError = "Purchase pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        if unlocked != isPro {
            isPro = unlocked
            UserDefaults.standard.set(unlocked, forKey: cacheKey)
            // The watch gates Shortcuts capture on this.
            PhoneLink.shared.pushDigest(MemoStore.shared.memos)
        }
    }
}

/// Features that live behind Wrist Pro.
enum ProFeature: String, Identifiable, CaseIterable {
    case ask, reminders, shortcuts, obsidian, byom, whisper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask Wrist, unlimited"
        case .reminders: "Send to Reminders"
        case .shortcuts: "Siri, Shortcuts & Action button"
        case .obsidian: "Obsidian vault sync"
        case .byom: "Bring your own model"
        case .whisper: "Whisper transcription models"
        }
    }

    var detail: String {
        switch self {
        case .ask: "Question everything you've captured, from your phone or wrist."
        case .reminders: "Turn to-dos into reminders in one tap."
        case .shortcuts: "Start a capture without opening the app."
        case .obsidian: "Every capture lands in your vault as Markdown — and in Claude via MCP."
        case .byom: "Claude, OpenAI, or a local model on your Mac (Ollama, LM Studio)."
        case .whisper: "Download on-device Whisper models for sharper transcripts."
        }
    }

    var symbol: String {
        switch self {
        case .ask: "sparkles"
        case .reminders: "checklist"
        case .shortcuts: "bolt"
        case .obsidian: "books.vertical"
        case .byom: "cpu"
        case .whisper: "waveform.badge.mic"
        }
    }
}
