import SwiftUI

/// Typed input is also a reliable simulator path; the system keyboard supports dictation.
struct NewNoteSheet: View {
    @EnvironmentObject private var store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Catch the thought. Keep the original.")
                    .font(.title2.bold())
                Text("Type a note or use keyboard dictation. Wrist will suggest a summary and to-dos; check them against what you said.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    .focused($focused)
                    .accessibilityLabel("Capture text")
                    .accessibilityIdentifier("note-text")
                if let error = store.storageError {
                    Text(error).font(.footnote).foregroundStyle(Theme.rose)
                }
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.ingestNote(text, source: .phone) { dismiss() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-note")
                }
            }
            .onAppear { focused = true }
        }
    }
}
