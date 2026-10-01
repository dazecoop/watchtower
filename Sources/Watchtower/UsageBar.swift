import SwiftUI

/// A slim strip along the bottom of the window showing plan usage. It sheds
/// detail as the window narrows rather than overflowing.
struct UsageBar: View {
    let usage: UsageSnapshot

    @Environment(\.theme) private var theme

    fileprivate enum Detail { case full, meter, minimal }

    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(.full, freshness: true)
                row(.full, freshness: false)
                row(.meter, freshness: false)
                row(.minimal, freshness: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if let style = theme.style {
                style.bar
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .opacity(isStale ? 0.55 : 1)
    }

    private func row(_ detail: Detail, freshness: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(usage.limits.enumerated()), id: \.element.id) { index, limit in
                if index > 0 {
                    Divider()
                        .frame(height: 12)
                        .padding(.horizontal, detail == .minimal ? 9 : 14)
                }
                UsageMeter(limit: limit, detail: detail)
            }

            if freshness, let fetched = usage.fetchedAt {
                Text(freshnessText(fetched))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 20)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func freshnessText(_ date: Date) -> String {
        let age = Date().timeIntervalSince(date)
        return age < 90 ? "just updated" : "updated \(shortDuration(age)) ago"
    }

    /// Claude Code refreshes these figures as it works; if nothing has for a
    /// while, dim the bar rather than present old numbers as current.
    private var isStale: Bool {
        guard let fetched = usage.fetchedAt else { return true }
        return Date().timeIntervalSince(fetched) > 30 * 60
    }

    fileprivate struct UsageMeter: View {
        let limit: UsageLimit
        let detail: Detail

        private var tint: Color {
            switch limit.level {
            case 2: return Color(red: 0.95, green: 0.35, blue: 0.35)
            case 1: return .waitingAmber
            default: return Color(red: 0.32, green: 0.60, blue: 0.98)
            }
        }

        var body: some View {
            HStack(spacing: detail == .minimal ? 5 : 7) {
                Text(detail == .minimal ? limit.shortLabel : limit.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                if detail != .minimal {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 70, height: 4)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(2, 70 * min(1, Double(limit.percent) / 100)), height: 4)
                    }
                    .animation(.easeOut(duration: 0.4), value: limit.percent)
                }

                Text("\(limit.percent)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(detail == .minimal ? tint : .primary.opacity(0.8))
                    .fixedSize()

                if detail == .full, let resets = limit.resetsAt {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text(shortDuration(resets.timeIntervalSinceNow))
                            .font(.system(size: 9.5, design: .monospaced))
                    }
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                }
            }
        }

    }
}
