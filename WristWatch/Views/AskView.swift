import SwiftUI

/// "Ask your memory": dictate a question, the iPhone answers from your captures.
struct AskView: View {
    @EnvironmentObject private var link: WatchLink
    @State private var question: String?
    @State private var answer: String?
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextFieldLink(prompt: Text("Ask about your captures")) {
                    Label("Ask Wrist", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .foregroundStyle(.white)
                } onSubmit: { text in
                    Task { await ask(text) }
                }
                .buttonStyle(.plain)

                if let question {
                    Text(question)
                        .font(.footnote.italic())
                        .foregroundStyle(Theme.softInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isAsking {
                    ProgressView()
                } else if let answer {
                    Text(answer)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if question == nil {
                    Text("Try “What did I promise Sam?”")
                        .font(.caption)
                        .foregroundStyle(Theme.softInk)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ask")
    }

    private func ask(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        question = trimmed
        answer = nil
        isAsking = true
        defer { isAsking = false }
        do {
            answer = try await link.ask(trimmed)
        } catch {
            answer = error.localizedDescription
        }
    }
}
