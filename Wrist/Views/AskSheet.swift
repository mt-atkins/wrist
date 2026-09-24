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
                            Text("Ask anything about your captures.")
                                .foregroundStyle(.secondary)
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { Task { await ask(suggestion) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                        ForEach(turns) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(turn.question)
                                    .font(.headline)
                                if let answer = turn.answer {
                                    Text(answer)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
