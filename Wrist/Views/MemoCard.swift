import SwiftUI

struct MemoCard: View {
    let memo: Memo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: memo.source.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.softInk)
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(memo.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.paper)

                if !memo.summary.isEmpty {
                    Text(memo.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.softInk)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(memo.createdAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    if memo.duration > 0 { Text("· \(memo.duration.clock)") }
                    if memo.openActionCount > 0 {
                        Text("· \(memo.openActionCount) to-do")
                            .foregroundStyle(Theme.orange)
                    }
                    Spacer(minLength: 0)
                    StatusChip(status: memo.status)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.machineGrey)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 14)
    }
}

/// Dot + explicit label; blue while working, red on failure, hidden when ready.
struct StatusChip: View {
    let status: MemoStatus

    var body: some View {
        if status != .ready {
            HStack(spacing: 5) {
                StatusDot(color: status == .failed ? Theme.red : Theme.blue)
                Text(status.label.lowercased())
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(status == .failed ? Theme.red : Theme.softInk)
        }
    }
}

struct TagChip: View {
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous))
            .foregroundStyle(Theme.softInk)
    }
}
