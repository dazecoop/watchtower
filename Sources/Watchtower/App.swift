import SwiftUI

@main
struct WatchtowerApp: App {
    @StateObject private var store = FleetStore()
    @StateObject private var overlay = OverlayController()

    /// Deliberately @AppStorage rather than a store property: MenuBarExtra
    /// writes back to this binding while updating, which through an
    /// ObservableObject becomes an endless publish/render loop.
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false

    var body: some Scene {
        WindowGroup("Watchtower", id: AppWindow.id) {
            RootView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    overlay.attach(to: store)
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands { WatchtowerCommands(store: store) }

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        // The string-label initializer is used deliberately: a ViewBuilder
        // label here nests the scene's generic types deeply enough to crash
        // the runtime while resolving metadata.
        MenuBarExtra(store.menuBarSummary, isInserted: $showMenuBarExtra) {
            MenuBarContent()
                .environmentObject(store)
        }

    }
}

/// Kept deliberately flat. Nesting the session list, dividers and actions in
/// one view made the generic type deep enough to crash the runtime.
private struct MenuBarContent: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        MenuBarRows()
        Divider()
        MenuBarUsage()
        Button("Open Watchtower") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            AppWindow.reopen?()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Watchtower") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct MenuBarRows: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        if store.visible.isEmpty {
            Text("No Claude sessions running")
        }
        ForEach(store.visible) { session in
            Button(rowTitle(session)) {
                store.focus(session)
            }
        }
    }

    private func rowTitle(_ session: SessionSnapshot) -> String {
        let mark: String
        switch session.state {
        case .working: mark = "●"
        case .waiting: mark = "◐"
        case .dormant: mark = "○"
        }
        return "\(mark)  \(session.name) — \(session.state.label)"
    }
}

/// The plan limits as one disabled line each, so the menu answers "how much
/// have I got left" without opening the window.
private struct MenuBarUsage: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        if let usage = store.usage, !usage.limits.isEmpty {
            ForEach(usage.limits) { limit in
                Text(line(limit, stale: usage.stale))
            }
            Divider()
        }
    }

    private func line(_ limit: UsageLimit, stale: Bool) -> String {
        var s = "\(limit.label)  \(limit.figure)"
        if limit.expired {
            s += "  · window reset"
        } else if let resets = limit.resetsAt {
            s += "  · resets in \(shortDuration(resets.timeIntervalSinceNow))"
        }
        return stale ? s + "  (not current)" : s
    }
}

/// Kept as its own `Commands` type: inlining these into the scene builder made
/// the nested opaque types deep enough to blow the stack during runtime
/// metadata resolution.
struct WatchtowerCommands: Commands {
    @ObservedObject var store: FleetStore

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh Now") { store.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button(store.paused ? "Resume Updates" : "Pause Updates") { store.paused.toggle() }
                .keyboardShortcut("p", modifiers: .command)
            Button(store.activeOnly ? "Show All Sessions" : "Show Active Only") {
                store.activeOnly.toggle()
            }
            .keyboardShortcut("l", modifiers: .command)
            Button(store.hasCleanedUp ? "Show Cleaned Up Sessions" : "Clean Up Idle Sessions") {
                if store.hasCleanedUp { store.restoreCleanedUp() } else { store.cleanUp() }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!store.hasCleanedUp && store.cleanableCount == 0)
            Button(store.showOverlay ? "Hide Overlay" : "Show Overlay") {
                store.showOverlay.toggle()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // ⌘1–⌘9 jump to the editor window of the first nine tiles, in the
        // order they sit on screen. The grid holds its order while work is
        // happening precisely so that a number keeps meaning the same tile.
        CommandMenu("Session") {
            JumpItems(store: store)
        }
    }
}

/// Its own type for the same reason as the rest: nine buttons inside a
/// `ForEach` inside a `CommandMenu` is more nesting than the scene builder
/// comfortably takes inline.
private struct JumpItems: View {
    @ObservedObject var store: FleetStore

    var body: some View {
        ForEach(0..<9, id: \.self) { index in
            let session = store.visible.indices.contains(index) ? store.visible[index] : nil
            Button(session.map { "Jump to \($0.name)" } ?? "Jump to Session \(index + 1)") {
                store.focus(index: index)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            .disabled(session == nil || !store.axTrusted)
        }
    }
}
