import SwiftUI

@main
struct WatchtowerApp: App {
    @StateObject private var store = FleetStore()
    @StateObject private var overlay = OverlayController()
    @StateObject private var menuBar = MenuBarController()

    var body: some Scene {
        WindowGroup("Watchtower", id: AppWindow.id) {
            RootView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    overlay.attach(to: store)
                    menuBar.attach(to: store)
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands { WatchtowerCommands(store: store) }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
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
