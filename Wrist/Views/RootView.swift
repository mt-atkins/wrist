import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MemoStore
    @State private var search = ""
    @State private var showAsk = false

    private var filtered: [Memo] {
        guard !search.isEmpty else { return store.memos }
        return store.memos.filter {
            ($0.title + " " + $0.summary + " " + $0.transcript + " " + $0.tags.joined(separator: " "))
                .localizedCaseInsensitiveContains(search)
        }
    }

    private var openActions: Int { store.memos.reduce(0) { $0 + $1.openActionCount } }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()

                if store.memos.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            StatsHeader(captures: store.memos.count, openActions: openActions)
                            ForEach(filtered) { memo in
                                NavigationLink(value: memo.id) {
                                    MemoCard(memo: memo)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        withAnimation { store.delete(memo.id) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 140)
                    }
                    .searchable(text: $search, prompt: "Search captures")
                }

                CaptureBar()
            }
            .navigationTitle("Wrist")
            .navigationDestination(for: UUID.self) { MemoDetailView(memoID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAsk = true
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: $showAsk) { AskSheet() }
        }
    }
}

private struct StatsHeader: View {
    let captures: Int
    let openActions: Int

    var body: some View {
        HStack(spacing: 10) {
            stat("\(captures)", "captures", "waveform")
            stat("\(openActions)", "open to-dos", "checklist")
            stat(Summarizer.usesAppleIntelligence ? "On" : "Lite", "on-device AI", "apple.intelligence")
        }
        .padding(.top, 4)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var store: MemoStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Your second brain lives on your wrist")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Raise your wrist, tap the orb, and talk. Wrist transcribes, summarizes and pulls out your to-dos — all on device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try a sample capture", systemImage: "sparkles") {
                store.addSample()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .padding(.bottom, 120)
    }
}
