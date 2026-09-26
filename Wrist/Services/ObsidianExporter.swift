import Foundation
import Combine

/// Writes captures into an Obsidian vault the user picked with the Files picker.
/// One Markdown note per capture (YAML frontmatter + Tasks-style checkboxes), rewritten in place
/// when the capture changes. Notes are never deleted by Wrist: the vault is the user's.
@MainActor
final class ObsidianExporter: ObservableObject {
    static let shared = ObsidianExporter()

    @Published private(set) var vaultDisplayName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastExport: Date?

    private let bookmarkKey = "obsidian.vaultBookmark"
    private let indexKey = "obsidian.index"
    /// memoID → note path relative to the vault, plus whether the daily note already links it.
    private var index: [String: IndexEntry]

    private struct IndexEntry: Codable {
        var path: String
        var linkedInDaily: Bool
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: indexKey),
           let decoded = try? JSONDecoder().decode([String: IndexEntry].self, from: data) {
            index = decoded
        } else {
            index = [:]
        }
        vaultDisplayName = (try? resolveVault())?.lastPathComponent
    }

    var isConnected: Bool { vaultDisplayName != nil }

    // MARK: Vault

    /// Call with the folder URL from `.fileImporter(allowedContentTypes: [.folder])`.
    func connect(vault url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Wrist couldn't get access to that folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            vaultDisplayName = url.lastPathComponent
            var settings = AppSettings.shared.obsidian
            settings.enabled = true
            if settings.vaultName.isEmpty { settings.vaultName = url.lastPathComponent }
            AppSettings.shared.obsidian = settings
            lastError = nil
        } catch {
            lastError = "Couldn't remember the vault: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        vaultDisplayName = nil
        AppSettings.shared.obsidian.enabled = false
    }

    private func resolveVault() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    // MARK: Export

    /// Called when a capture becomes ready or its to-dos change. Pro only.
    func exportIfEnabled(_ memo: Memo) {
        guard ProStore.shared.isPro, AppSettings.shared.obsidian.enabled else { return }
        _ = export(memo)
    }

    /// Exports one capture. Returns the note's path in the vault, or nil on failure.
    @discardableResult
    func export(_ memo: Memo) -> String? {
        let settings = AppSettings.shared.obsidian
        do {
            guard let vault = try resolveVault() else {
                lastError = "Choose your Obsidian vault in Settings first."
                return nil
            }
            guard vault.startAccessingSecurityScopedResource() else {
                lastError = "Access to the vault expired. Choose it again in Settings."
                return nil
            }
            defer { vault.stopAccessingSecurityScopedResource() }

            let relative = Self.notePath(for: memo, folder: settings.folder)
            let previous = index[memo.id.uuidString]
            try write(Self.markdown(for: memo), to: vault.appendingPathComponent(relative))

            // A new title means a new file name: remove our old note, but only if it is still ours.
            if let old = previous?.path, old != relative {
                let oldURL = vault.appendingPathComponent(old)
                if let text = try? String(contentsOf: oldURL, encoding: .utf8), text.contains("wrist-id: \(memo.id.uuidString)") {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }

            var linked = previous?.linkedInDaily ?? false
            if settings.linkInDailyNote, !linked {
                try appendDailyLink(for: memo, notePath: relative, settings: settings, vault: vault)
                linked = true
            }
            index[memo.id.uuidString] = IndexEntry(path: relative, linkedInDaily: linked)
            saveIndex()
            lastError = nil
            lastExport = Date()
            return relative
        } catch {
            lastError = "Obsidian export failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Exports every ready capture (e.g. right after connecting a vault).
    func exportAll(_ memos: [Memo]) -> Int {
        memos.filter { $0.status == .ready }.reduce(0) { $0 + (export($1) == nil ? 0 : 1) }
    }

    /// obsidian://open?vault=…&file=… for the "Open in Obsidian" button.
    func openURL(for memo: Memo) -> URL? {
        let settings = AppSettings.shared.obsidian
        guard let path = index[memo.id.uuidString]?.path, !settings.vaultName.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: settings.vaultName),
            URLQueryItem(name: "file", value: path),
        ]
        return components.url
    }

    private func appendDailyLink(for memo: Memo, notePath: String, settings: ObsidianSettings, vault: URL) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = settings.dailyFormat.isEmpty ? "yyyy-MM-dd" : settings.dailyFormat
        let dailyName = formatter.string(from: memo.createdAt) + ".md"
        let folder = settings.dailyFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let dailyURL = folder.isEmpty ? vault.appendingPathComponent(dailyName)
                                      : vault.appendingPathComponent(folder).appendingPathComponent(dailyName)
        let time = memo.createdAt.formatted(date: .omitted, time: .shortened)
        let link = notePath.hasSuffix(".md") ? String(notePath.dropLast(3)) : notePath
        let line = "- \(time) [[\(link)|\(memo.displayTitle)]]\n"

        var existing = (try? String(contentsOf: dailyURL, encoding: .utf8)) ?? ""
        guard !existing.contains("[[\(link)|") else { return }
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        try write(existing + line, to: dailyURL)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Coordinate so iCloud Drive / Obsidian Sync see a clean write.
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { target in
            do { try Data(text.utf8).write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinatorError ?? writeError { throw error }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(index) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }

    // MARK: Formatting (pure, unit-tested)

    nonisolated static func notePath(for memo: Memo, folder: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let title = memo.displayTitle.components(separatedBy: unsafe).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = "\(formatter.string(from: memo.createdAt)) \(title.prefix(60)).md"
        let cleanFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
    }

    nonisolated static func markdown(for memo: Memo) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let summaryBy: String = switch memo.insightSource {
        case .appleIntelligence: "apple-intelligence"
        case .ownModel: memo.insightModel ?? "own-model"
        case .heuristic, .silent, .none: "local-rules"
        }
        var lines = [
            "---",
            "wrist-id: \(memo.id.uuidString)",
            "created: \(iso.string(from: memo.createdAt))",
            "source: \(memo.source.rawValue)",
        ]
        if memo.duration > 0 { lines.append("duration: \(Int(memo.duration.rounded()))") }
        lines.append("transcribed-by: \(yamlValue(memo.transcriptModel ?? "apple-speech"))")
        lines.append("summarized-by: \(yamlValue(summaryBy))")
        lines.append("tags: [\((["wrist"] + memo.tags).joined(separator: ", "))]")
        lines.append("---")
        lines.append("")
        lines.append("# \(memo.displayTitle)")
        lines.append("")
        if !memo.summary.isEmpty {
            lines.append(memo.summary)
            lines.append("")
        }
        if !memo.actionItems.isEmpty {
            lines.append("## To-dos")
            lines += memo.actionItems.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
            lines.append("")
        }
        if !memo.transcript.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            lines.append(memo.transcript)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func yamlValue(_ value: String) -> String {
        value.contains(where: { ":#[]{},".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "'"))\"" : value
    }
}
