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
        .opacity(usage.stale ? 0.55 : 1)
    }

    private func row(_ detail: Detail, freshness: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(usage.limits.enumerated()), id: \.element.id) { index, limit in
                if index > 0 {
                    Divider()
                        .frame(height: 12)
                        .padding(.horizontal, detail == .minimal ? 9 : 14)
                }
                UsageMeter(limit: limit, index: index, detail: detail)
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

    fileprivate struct UsageMeter: View {
        let limit: UsageLimit
        let index: Int
        let detail: Detail

        private var tint: Color { .forLimit(index) }

        /// An expired window has no figure to show: the percentage belongs to
        /// a window that has already rolled over, and the new one is unknown
        /// until Claude Code polls again.
        private var fraction: Double { limit.expired ? 0 : min(1, Double(limit.percent) / 100) }

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
                            .frame(width: max(2, 70 * fraction), height: 4)
                            .opacity(limit.expired ? 0 : 1)
                    }
                    .animation(.easeOut(duration: 0.4), value: fraction)
                }

                Text(limit.figure)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(limit.expired
                                     ? Color.primary.opacity(0.35)
                                     : (Color.forSeverity(limit.level)
                                        ?? (detail == .minimal ? tint : .primary.opacity(0.8))))
                    .fixedSize()

                if detail == .full, limit.expired {
                    Text("window reset")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                } else if detail == .full, let resets = limit.resetsAt {
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
