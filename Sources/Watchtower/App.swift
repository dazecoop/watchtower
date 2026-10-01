import SwiftUI

@main
struct WatchtowerApp: App {
    @StateObject private var store = FleetStore()

    /// Deliberately @AppStorage rather than a store property: MenuBarExtra
    /// writes back to this binding while updating, which through an
    /// ObservableObject becomes an endless publish/render loop.
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false

    var body: some Scene {
        WindowGroup("Watchtower") {
            RootView()
                .environmentObject(store)
                .onAppear { store.start() }
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
        Button("Open Watchtower") {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Quit Watchtower") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct MenuBarRows: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
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
        }
    }
}
