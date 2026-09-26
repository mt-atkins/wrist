import SwiftUI

struct MemoDetailView: View {
    @EnvironmentObject private var store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var showTranscript = false
    @State private var exportMessage: String?
    @State private var paywall: ProFeature?
    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var obsidian: ObsidianExporter
    @Environment(\.openURL) private var openURL

    let memoID: UUID

    var body: some View {
        if let memo = store.memo(memoID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(memo)
                    if let file = memo.audioFileName { playerRow(url: store.audioURL(for: file), duration: memo.duration) }
                    if let error = memo.errorMessage, memo.status == .failed { failure(error) }
                    if !memo.summary.isEmpty {
                        section("Summary") {
                            Text(memo.summary)
                            Text(provenance(memo))
                                .font(.caption).foregroundStyle(Theme.machineGrey)
                        }
                    }
                    if !memo.actionItems.isEmpty { actions(memo) }
                    if !memo.transcript.isEmpty { transcript(memo) }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: markdown(for: memo)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Menu {
                        Button("Reprocess capture", systemImage: "arrow.clockwise") { store.process(memo.id) }
                        Button(obsidian.openURL(for: memo) == nil ? "Save to Obsidian" : "Open in Obsidian", systemImage: "books.vertical") {
                            guard pro.isPro else { paywall = .obsidian; return }
                            if let url = obsidian.openURL(for: memo) {
                                obsidian.export(memo)
                                openURL(url)
                            } else if obsidian.export(memo) != nil, let url = obsidian.openURL(for: memo) {
                                openURL(url)
                            } else {
                                exportMessage = obsidian.lastError
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            if store.delete(memo.id) { dismiss() }
                        }
                        .accessibilityIdentifier("delete-memo")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("memo-menu")
                }
            }
            .sheet(item: $paywall) { PaywallView(highlight: $0) }
        } else {
            ContentUnavailableView("Capture deleted", systemImage: "trash")
        }
    }

    private func header(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: memo.source.symbol)
                Text(memo.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                StatusChip(status: memo.status)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.machineGrey)
            Text(memo.displayTitle)
                .font(.largeTitle.bold())
                .kerning(-0.8)
                .foregroundStyle(Theme.paper)
            if !memo.tags.isEmpty {
                HStack { ForEach(memo.tags, id: \.self) { TagChip(tag: $0) } }
            }
        }
    }

    private func playerRow(url: URL, duration: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.orange, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .foregroundStyle(.white)
            }
            ProgressView(value: player.progress)
                .tint(Theme.orange)
            Text(duration.clock)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.machineGrey)
        }
        .panel(padding: 12)
    }

    private func failure(_ error: String) -> some View {
        HStack {
            StatusDot(color: Theme.red)
            Text(error).font(.footnote).foregroundStyle(Theme.paper)
            Spacer()
            Button("Retry") { store.process(memoID) }
        }
        .padding(12)
        .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).stroke(Theme.red.opacity(0.4)))
    }

    private func actions(_ memo: Memo) -> some View {
        section("To-dos") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(memo.actionItems) { item in
                    Button {
                        withAnimation { store.setAction(item.id, in: memo.id, done: !item.isDone) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Theme.machineGrey : Theme.orange)
                            Text(item.text)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? Theme.machineGrey : Theme.paper)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if memo.openActionCount > 0 {
                    Button {
                        if pro.isPro { Task { await exportReminders(memo) } } else { paywall = .reminders }
                    } label: {
                        Label("Send to Reminders", systemImage: "checklist")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).stroke(Theme.line))
                            .foregroundStyle(Theme.paper)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(Theme.machineGrey)
                }
            }
        }
    }

    private func transcript(_ memo: Memo) -> some View {
        section("Transcript") {
            VStack(alignment: .leading, spacing: 8) {
                Text(memo.transcript)
                    .lineLimit(showTranscript ? nil : 4)
                    .foregroundStyle(Theme.softInk)
                    .textSelection(.enabled)
                Button(showTranscript ? "Show less" : "Show full transcript") {
                    withAnimation { showTranscript.toggle() }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
                .foregroundStyle(Theme.paper)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func provenance(_ memo: Memo) -> String {
        var parts: [String] = []
        switch memo.insightSource {
        case .appleIntelligence: parts.append("Apple Intelligence · check against the transcript")
        case .ownModel: parts.append("\(memo.insightModel ?? "Your model") · check against the transcript")
        default: parts.append("Local rules · extracted from your words, not an AI summary")
        }
        if let model = memo.transcriptModel { parts.append("Transcribed by \(model)") }
        if let note = memo.insightNote { parts.append(note) }
        return parts.joined(separator: "\n")
    }

    private func exportReminders(_ memo: Memo) async {
        do {
            let count = try await RemindersExporter.export(memo.actionItems, from: memo.displayTitle)
            exportMessage = "Added \(count) reminder\(count == 1 ? "" : "s")."
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    /// Paste-ready note for Apple Notes, Obsidian, Notion, etc.
    private func markdown(for memo: Memo) -> String {
        var lines = ["# \(memo.displayTitle)", ""]
        if !memo.summary.isEmpty { lines += [memo.summary, ""] }
        if !memo.actionItems.isEmpty {
            lines.append("## To-dos")
            lines += memo.actionItems.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
            lines.append("")
        }
        if !memo.tags.isEmpty { lines += [memo.tags.map { "#\($0)" }.joined(separator: " "), ""] }
        if !memo.transcript.isEmpty { lines += ["## Transcript", memo.transcript] }
        return lines.joined(separator: "\n")
    }
}
