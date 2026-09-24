import SwiftUI

struct MemoDetailView: View {
    @EnvironmentObject private var store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var showTranscript = false
    @State private var exportMessage: String?

    let memoID: UUID

    var body: some View {
        if let memo = store.memo(memoID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(memo)
                    if let file = memo.audioFileName { playerRow(url: store.audioURL(for: file), duration: memo.duration) }
                    if let error = memo.errorMessage, memo.status == .failed { failure(error) }
                    if !memo.summary.isEmpty { section("Summary") { Text(memo.summary) } }
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
                        Button("Re-run AI", systemImage: "arrow.clockwise") { store.process(memo.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.delete(memo.id)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        } else {
            ContentUnavailableView("Capture deleted", systemImage: "trash")
        }
    }

    private func header(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: memo.source.symbol)
                Text(memo.createdAt, format: .dateTime.month().day().hour().minute())
                StatusChip(status: memo.status)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(memo.displayTitle)
                .font(.largeTitle.bold())
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
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.white)
            }
            ProgressView(value: player.progress)
                .tint(Theme.ember)
            Text(duration.clock)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func failure(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.rose)
            Text(error).font(.footnote)
            Spacer()
            Button("Retry") { store.process(memoID) }
        }
        .padding(12)
        .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                .foregroundStyle(item.isDone ? Color.secondary : Theme.ember)
                            Text(item.text)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if memo.openActionCount > 0 {
                    Button("Send to Reminders", systemImage: "checklist") {
                        Task { await exportReminders(memo) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transcript(_ memo: Memo) -> some View {
        section("Transcript") {
            VStack(alignment: .leading, spacing: 8) {
                Text(memo.transcript)
                    .lineLimit(showTranscript ? nil : 4)
                    .foregroundStyle(.secondary)
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
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .kerning(1.2)
                .foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
