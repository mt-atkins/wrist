import SwiftUI

struct MemoCard: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: memo.source.symbol)
                Text(memo.createdAt, format: .dateTime.weekday().hour().minute())
                if memo.duration > 0 {
                    Text("· \(memo.duration.clock)")
                }
                Spacer()
                StatusChip(status: memo.status)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(memo.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            if !memo.summary.isEmpty {
                Text(memo.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if memo.openActionCount > 0 || !memo.tags.isEmpty {
                HStack(spacing: 6) {
                    if memo.openActionCount > 0 {
                        Label("\(memo.openActionCount)", systemImage: "checklist")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ember)
                    }
                    ForEach(memo.tags, id: \.self) { TagChip(tag: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
    }
}

struct StatusChip: View {
    let status: MemoStatus

    var body: some View {
        if status != .ready {
            HStack(spacing: 4) {
                if status.isWorking { ProgressView().controlSize(.mini) }
                Text(status.label)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((status == .failed ? Theme.rose : Theme.violet).opacity(0.25), in: Capsule())
        }
    }
}

struct TagChip: View {
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
