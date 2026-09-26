import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss
    /// The feature that sent the user here, highlighted first.
    var highlight: ProFeature?

    private var features: [ProFeature] {
        guard let highlight else { return ProFeature.allCases }
        return [highlight] + ProFeature.allCases.filter { $0 != highlight }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        (Text("Wrist Pro").foregroundStyle(Theme.paper) + Text(".").foregroundStyle(Theme.orange))
                            .font(.system(size: 34, weight: .bold))
                        Text("Capture and summaries stay free forever. Pro adds the power tools.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.softInk)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.element) { index, feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: feature.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(feature == highlight ? Theme.orange : Theme.paper)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Theme.line))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.paper)
                                    Text(feature.detail).font(.footnote).foregroundStyle(Theme.softInk)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            if index < features.count - 1 {
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                        }
                    }
                    .panel(padding: 0)

                    if pro.isPro {
                        HStack(spacing: 8) {
                            StatusDot(color: Theme.green)
                            Text("Wrist Pro is unlocked. Thank you.")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.paper)
                    } else {
                        Button {
                            Task {
                                await pro.purchase()
                                if pro.isPro { dismiss() }
                            }
                        } label: {
                            HStack {
                                if pro.isPurchasing { ProgressView().tint(.white) }
                                Text(pro.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock Wrist Pro")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.orange, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(pro.product == nil || pro.isPurchasing)
                        .accessibilityIdentifier("buy-pro")

                        SectionLabel("One-time purchase · No subscription · Family Sharing")
                            .frame(maxWidth: .infinity)
                    }

                    if let error = pro.lastError {
                        Text(error).font(.footnote).foregroundStyle(Theme.red)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { Task { await pro.restore() } }
                }
            }
        }
    }
}

/// Small "PRO" tag next to locked features.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.orange)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tag).stroke(Theme.orange.opacity(0.6)))
    }
}
