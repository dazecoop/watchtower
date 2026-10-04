import SwiftUI

/// What the status item's `NSPopover` shows: the same "what's going on right
/// now" summary the notch gives, laid out as readable rows instead of one
/// tooltip string — network and awake status up top, then sessions, then
/// usage, then the window/settings/quit actions the old `NSMenu` carried.
struct MenuBarPopoverView: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showsStatus {
                Divider()
                statusRows
            }
            if !store.visible.isEmpty {
                Divider()
                sessionRows
            }
            if let usage = store.usage, !usage.limits.isEmpty {
                Divider()
                usageRows(usage)
            }
            Divider()
            actions
        }
        .padding(.vertical, 6)
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: fleetSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(fleetColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Watchtower").font(.system(size: 13, weight: .semibold))
                Text(fleetSummary).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var fleetSymbol: String {
        if store.workingCount > 0 { return "bolt.fill" }
        if store.waitingCount > 0 { return "clock.fill" }
        return "checkmark.circle.fill"
    }

    private var fleetColor: Color {
        if store.workingCount > 0 { return .workingGreen }
        if store.waitingCount > 0 { return .waitingAmber }
        return .dormantGray
    }

    private var fleetSummary: String {
        if store.workingCount > 0 && store.waitingCount > 0 {
            return "\(store.workingCount) working · \(store.waitingCount) waiting"
        }
        if store.workingCount > 0 { return "\(store.workingCount) working" }
        if store.waitingCount > 0 { return "\(store.waitingCount) waiting" }
        return store.sessions.isEmpty ? "No sessions running" : "All quiet"
    }

    // MARK: Status

    private var showsStatus: Bool { store.checkInternet || store.keepAwake }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.checkInternet {
                HStack(spacing: 8) {
                    NetDot(status: store.netStatus, size: 8)
                    Text(store.netStatus.label).font(.system(size: 12))
                    Spacer()
                }
            }
            if store.keepAwake {
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(store.isHoldingAwake ? Color.workingGreen : Color.dormantGray)
                        .frame(width: 8, alignment: .center)
                    Text(awakeLabel).font(.system(size: 12))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var awakeLabel: String {
        guard store.isHoldingAwake else { return "Awake guard idle" }
        return store.preventDisplaySleep ? "Keeping Mac and display awake" : "Keeping Mac awake"
    }

    // MARK: Sessions

    private var sessionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.visible.prefix(8)) { session in
                MenuRow {
                    store.focus(session)
                } content: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.forState(session.state))
                            .frame(width: 7, height: 7)
                        Text(session.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(session.state.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Usage

    private func usageRows(_ usage: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(usage.limits.prefix(3).enumerated()), id: \.element.id) { index, limit in
                HStack(spacing: 8) {
                    Text(limit.label).font(.system(size: 12))
                    MenuBarUsageHairline(
                        percent: limit.expired ? 0 : limit.percent,
                        color: .forLimit(index),
                        width: 28,
                        height: 3
                    )
                    Spacer()
                    Text(usageFigure(limit))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.forSeverity(limit.level) ?? .secondary)
                }
            }
            if usage.stale {
                Text("Figures not current").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func usageFigure(_ limit: UsageLimit) -> String {
        guard !limit.expired, let resets = limit.resetsAt else { return limit.figure }
        return "\(limit.figure) · \(shortDuration(resets.timeIntervalSinceNow))"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow {
                NSApplication.shared.activate(ignoringOtherApps: true)
                AppWindow.reopen?()
            } content: {
                Label("Open Watchtower", systemImage: "macwindow")
                    .font(.system(size: 12))
            }
            SettingsLink {
                MenuRowLabel {
                    Label("Settings…", systemImage: "gearshape")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            MenuRow {
                NSApplication.shared.terminate(nil)
            } content: {
                Label("Quit Watchtower", systemImage: "power")
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 2)
    }
}

/// A menu-like row: plain until hovered, then tinted so the popover still
/// reads as a dropdown rather than a loose stack of buttons.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            MenuRowLabel(content: { content })
        }
        .buttonStyle(.plain)
    }
}

private struct MenuRowLabel<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
            .onHover { hovering = $0 }
    }
}
