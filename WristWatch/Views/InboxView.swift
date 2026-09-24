import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var link: WatchLink

    var body: some View {
        Group {
            if link.memos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text("Captures show up here once your iPhone has summarized them.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List(link.memos) { memo in
                    NavigationLink(value: memo.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(memo.displayTitle)
                                .font(.headline)
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                if memo.status.isWorking {
                                    ProgressView().controlSize(.mini)
                                    Text(memo.status.label)
                                } else {
                                    Text(memo.createdAt, style: .relative)
                                    if memo.openActionCount > 0 {
                                        Text("· \(memo.openActionCount) to-do")
                                            .foregroundStyle(Theme.ember)
                                    }
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .navigationDestination(for: UUID.self) { id in
            WatchMemoDetailView(memoID: id)
        }
    }
}

struct WatchMemoDetailView: View {
    @EnvironmentObject private var link: WatchLink
    let memoID: UUID

    var body: some View {
        if let memo = link.memos.first(where: { $0.id == memoID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(memo.displayTitle)
                        .font(.headline)
                    if !memo.summary.isEmpty {
                        Text(memo.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(memo.actionItems) { item in
                        Button {
                            link.setAction(item.id, in: memo.id, done: !item.isDone)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? Color.secondary : Theme.ember)
                                Text(item.text)
                                    .font(.footnote)
                                    .strikethrough(item.isDone)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("This capture is gone.")
        }
    }
}
