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

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Header()
                        if store.memos.isEmpty {
                            EmptyStateView()
                        } else {
                            StatsStrip(captures: store.memos.count, openActions: openActions)
                            HStack {
                                SectionLabel("Captures")
                                Spacer()
                                SectionLabel("\(filtered.count)")
                            }
                            .padding(.top, 12)
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 140)
                }
                .searchable(text: $search, prompt: "Search captures")

                CaptureBar()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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

private struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Wordmark(size: 34)
            Text(Date(), format: .dateTime.day().month(.abbreviated).year())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.machineGrey)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct StatsStrip: View {
    let captures: Int
    let openActions: Int

    var body: some View {
        HStack(spacing: 0) {
            stat("\(captures)", "Captures")
            divider
            stat("\(openActions)", "Open to-dos")
            divider
            stat(Summarizer.usesAppleIntelligence ? "On" : "Lite", "On-device AI")
        }
        .panel(padding: 0)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.paper)
            SectionLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var store: MemoStore

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Scanlines()
                OrbView(level: 0, isActive: false, symbolSize: 26)
                    .frame(width: 84, height: 84)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).stroke(Theme.line))

            VStack(spacing: 8) {
                Text("Your second brain, on your wrist")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.paper)
                Text("Raise your wrist, tap the orb and talk. Wrist transcribes, summarizes and pulls out your to-dos, all on device.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.softInk)
            }

            Button {
                store.addSample()
            } label: {
                Label("Try a sample capture", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.orange, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}
