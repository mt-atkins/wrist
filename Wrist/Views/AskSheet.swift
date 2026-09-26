import SwiftUI

/// Chat with everything you've captured.
struct AskSheet: View {
    @EnvironmentObject private var store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var turns: [Turn] = []
    @State private var isThinking = false
    @FocusState private var focused: Bool

    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
    }

    private let suggestions = [
        "What do I still need to do?",
        "Summarize my week",
        "What did I say about the launch?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if turns.isEmpty {
                            Text(Summarizer.usesAppleIntelligence ? "Answers use relevant captures, not your Apple Notes library. Check the original before acting." : "Local keyword search is active. Replies are matching excerpts, not AI-generated answers.")
                                .font(.footnote)
                                .foregroundStyle(Theme.softInk)
                            SectionLabel("Try asking")
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { Task { await ask(suggestion) } } label: {
                                    HStack {
                                        Text(suggestion).foregroundStyle(Theme.paper)
                                        Spacer()
                                        Image(systemName: "arrow.right").foregroundStyle(Theme.orange)
                                    }
                                    .font(.subheadline)
                                    .panel(padding: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ForEach(turns) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(turn.question)
                                    .font(.headline)
                                    .foregroundStyle(Theme.paper)
                                if let answer = turn.answer {
                                    Text(answer)
                                        .foregroundStyle(Theme.softInk)
                                        .textSelection(.enabled)
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panel(padding: 14)
                            .id(turn.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: turns.count) {
                    if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Ask Wrist…", text: $input, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...4)
                        .onSubmit { Task { await ask(input) } }
                    Button {
                        Task { await ask(input) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).stroke(Theme.line))
                .padding(12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func ask(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        input = ""
        isThinking = true
        turns.append(Turn(question: question))
        let answer = await store.ask(question)
        turns[turns.count - 1].answer = answer
        isThinking = false
    }
}
