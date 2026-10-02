import AppKit
import SwiftUI

/// Shared numbers for the notch's swell, so the controller's geometry and the
/// view's animation can't drift apart.
///
/// None of this scales with the notch. The size slider sets how big the notch
/// itself sits on the bezel; once it is open it is a panel you are reading,
/// and a small notch has no business shipping eight-point type.
enum OverlayExpansion {
    /// How wide the open summary reads. Wide enough for a session name and
    /// what it's doing on one line.
    static let width: CGFloat = 360

    /// At most this many sessions get a row; the rest are summarised. A panel
    /// that grows without bound stops being a notch.
    static let maxRows = 5

    /// One spring drives both directions. `response` is roughly the time to
    /// reach the target, and the controller waits this long before it takes
    /// the panel's extra space back.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let settle: TimeInterval = 0.55

    /// The notch is pure black, so the grid inside it is drawn on that black
    /// rather than on a theme's own window colour — a slate or indigo panel
    /// inside a black bezel reads as a window someone forgot to close. Cards,
    /// borders and the usage strip still need colours, and Midnight's are the
    /// ones built for a near-black ground.
    static let appTheme: Theme = .midnight

    /// Sessions worth a row: whatever is working or waiting first, then the
    /// most recently quiet, so the panel leads with what needs you.
    @MainActor
    static func rows(_ store: FleetStore) -> [SessionSnapshot] {
        let ranked = store.listed.sorted {
            $0.state == $1.state ? $0.lastActivity > $1.lastActivity : $0.state < $1.state
        }
        return Array(ranked.prefix(maxRows))
    }

    /// How big the full-app panel opens. Generous but bounded, and never more
    /// than most of the screen — the grid scrolls, so it doesn't have to grow
    /// to fit every session.
    @MainActor
    static func appSize(screen: NSScreen) -> CGSize {
        let full = screen.frame
        return CGSize(width: min(980, full.width * 0.9),
                      height: min(720, full.height * 0.8))
    }

    /// Measures the open summary rather than predicting it. The content is
    /// laid out at a fixed width and allowed to find its own height, so the
    /// panel can never come up a row short and clip the list.
    @MainActor
    static func contentSize(store: FleetStore) -> CGSize {
        let probe = NSHostingView(rootView: AnyView(
            ExpandedPanel(measuring: true)
                .environmentObject(store)
                .environment(\.theme, OverlayExpansion.appTheme)
                .frame(width: width)
        ))
        probe.layoutSubtreeIfNeeded()
        return CGSize(width: width, height: max(probe.fittingSize.height.rounded(.up), 100))
    }
}

// MARK: - The summary panel

/// What the notch becomes once it has swelled open: the fleet at a glance,
/// without the main window coming forward over whatever you were doing.
struct ExpandedPanel: View {
    /// True while this is the throwaway copy being measured, where a tap
    /// target would be meaningless.
    var measuring = false
    var onOpenApp: () -> Void = {}
    var onPick: (SessionSnapshot) -> Void = { _ in }

    @EnvironmentObject private var store: FleetStore

    private var rows: [SessionSnapshot] { OverlayExpansion.rows(store) }
    private var limits: [UsageLimit] { Array((store.usage?.limits ?? []).prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if rows.isEmpty {
                Text(store.hasCleanedUp ? "All cleaned up" : "No Claude sessions running")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(rows) { session in
                        SessionRow(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture { if !measuring { onPick(session) } }
                    }
                }
            }

            if !limits.isEmpty {
                Divider().overlay(Color.white.opacity(0.10))
                limitsRow
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(headline)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            NotchStatus(store: store)

            Spacer(minLength: 0)

            if store.hasCleanedUp {
                NotchChip(text: "Show all") { if !measuring { store.restoreCleanedUp() } }
            } else if store.cleanableCount > 0 {
                NotchChip(text: "Clean up") { if !measuring { store.cleanUp() } }
            }

            NotchChip(text: "Open") { if !measuring { onOpenApp() } }
        }
    }

    private var headline: String {
        var parts: [String] = []
        if store.workingCount > 0 { parts.append("\(store.workingCount) working") }
        if store.waitingCount > 0 { parts.append("\(store.waitingCount) your turn") }
        if parts.isEmpty {
            let n = store.sessions.count
            return n == 0 ? "Watchtower" : "\(n) session\(n == 1 ? "" : "s"), all idle"
        }
        return parts.joined(separator: " · ")
    }

    private var limitsRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.forLimit(index))
                        .frame(width: 6, height: 6)
                    Text(limit.shortLabel)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(limit.figure)
                        .foregroundStyle(Color.forSeverity(limit.level) ?? .white.opacity(0.85))
                        .monospacedDigit()
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .opacity((store.usage?.stale ?? false) ? 0.55 : 1)
    }
}

/// One session, trimmed to what reads at a glance: what it is, what it just
/// did, and how long ago.
private struct SessionRow: View {
    let session: SessionSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.forState(session.state))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(shortDuration(Date().timeIntervalSince(session.lastActivity)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .opacity(session.state == .dormant ? 0.55 : 1)
    }

    private var detail: String {
        if let event = session.parsed.events.last, !event.detail.isEmpty {
            return event.detail.firstLine(max: 70)
        }
        return session.headline
    }
}

// MARK: - The whole app, in the notch

/// Watchtower's own grid, drawn inside the notch instead of in a window.
///
/// The window's chrome doesn't come along: a borderless panel has no toolbar,
/// so the counts and the controls that live in the title bar are rebuilt here
/// as a header strip. Everything below it is the same view the window uses.
struct ExpandedAppPanel: View {
    var onSettings: () -> Void = {}

    @EnvironmentObject private var store: FleetStore

    private var columns: [GridItem] {
        if store.columnCount > 0 {
            return Array(repeating: GridItem(.flexible(minimum: 220), spacing: 14),
                         count: store.columnCount)
        }
        return [GridItem(.adaptive(minimum: 320, maximum: 620), spacing: 14)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.visible.isEmpty {
                Spacer(minLength: 0)
                Text(store.emptyReason.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.visible) { session in
                            SessionTile(session: session)
                        }
                    }
                    .padding(14)
                    .animation(.easeInOut(duration: 0.25), value: store.visible.map(\.id))
                }
            }

            if let usage = store.usage, !usage.limits.isEmpty {
                Divider().overlay(Color.white.opacity(0.10))
                UsageBar(usage: usage)
            }
        }
        // Midnight's cards and bars, but none of its window colour: the notch
        // supplies the black underneath.
        .environment(\.theme, OverlayExpansion.appTheme)
        .environment(\.renderMarkdown, store.renderMarkdown)
        // A popover from a panel that never becomes key is unreliable, and
        // the window is one click away for anyone who wants the detail.
        .environment(\.inspectorEnabled, false)
    }

    /// Stands in for the window's toolbar. There is deliberately nothing here
    /// that summons the window: in this mode the notch *is* the app, so the
    /// cog opens Settings on its own rather than raising a window behind it.
    private var header: some View {
        HStack(spacing: 10) {
            if store.workingCount > 0 {
                NotchPill(count: store.workingCount, label: "working", color: .workingGreen)
            }
            if store.waitingCount > 0 {
                NotchPill(count: store.waitingCount, label: "your turn", color: .waitingAmber)
            }
            if store.workingCount == 0 && store.waitingCount == 0 {
                Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            NotchStatus(store: store)

            Spacer(minLength: 0)

            NotchControl(symbol: "bolt.fill", on: store.activeOnly, help: "Hide idle sessions") {
                store.activeOnly.toggle()
            }
            // In-app only: the sessions are left alone, and any that stirs
            // reappears on its own.
            if store.hasCleanedUp {
                NotchControl(symbol: "arrow.uturn.backward", on: true,
                             help: "Bring back the sessions you cleaned up") {
                    store.restoreCleanedUp()
                }
            } else if store.cleanableCount > 0 {
                NotchControl(symbol: "sparkles", on: false,
                             help: "Clean up: hide \(store.cleanableCount) idle session\(store.cleanableCount == 1 ? "" : "s") from Watchtower") {
                    store.cleanUp()
                }
            }
            NotchControl(symbol: store.paused ? "play.fill" : "pause.fill",
                         on: store.paused,
                         help: store.paused ? "Resume live updates" : "Pause live updates") {
                store.paused.toggle()
            }
            // SwiftUI's own way in. Sending `showSettingsWindow:` down the
            // responder chain goes nowhere from here — this panel refuses to
            // become key, by design — and driving the menu item by hand is no
            // better. `SettingsLink` doesn't care who is key. The gesture runs
            // alongside it, and places the window it opens.
            SettingsLink {
                NotchControlLabel(symbol: "gearshape", on: false)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .simultaneousGesture(TapGesture().onEnded { onSettings() })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared bits

/// Plain tap targets rather than Buttons: the panel never becomes key, and
/// controls that expect focus behave oddly in one.
private struct NotchChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }
}

private struct NotchPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct NotchControlLabel: View {
    let symbol: String
    let on: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(on ? 0.95 : 0.6))
            .frame(width: 24, height: 20)
            .background(Color.white.opacity(on ? 0.16 : 0.07),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
    }
}

private struct NotchControl: View {
    let symbol: String
    let on: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        NotchControlLabel(symbol: symbol, on: on)
            .onTapGesture(perform: action)
            .help(help)
    }
}


/// The connectivity dot and the awake icon, for the notch's two headers. Both
/// appear only when their setting is on, so the header stays empty for anyone
/// who wants neither.
private struct NotchStatus: View {
    @ObservedObject var store: FleetStore

    var body: some View {
        HStack(spacing: 6) {
            if store.checkInternet {
                NetDot(status: store.netStatus, size: 6)
            }
            if store.keepAwake {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(store.isHoldingAwake
                                     ? Color.workingGreen
                                     : .white.opacity(0.35))
            }
        }
    }
}
