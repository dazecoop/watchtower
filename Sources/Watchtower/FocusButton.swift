import SwiftUI

/// Jumps to the editor window hosting a session, switching Spaces if needed.
/// When the right window can't be inferred, it becomes a one-time picker.
///
/// The menu contents deliberately use a `Picker` rather than `Button`s: a
/// custom `buttonStyle` on the control leaks into the menu's contents and
/// renders every item disabled.
struct FocusButton: View {
    let session: SessionSnapshot

    @EnvironmentObject var store: FleetStore

    var body: some View {
        if !store.axTrusted {
            Button {
                store.requestAccessibility()
            } label: {
                label(icon: "lock.fill")
            }
            .buttonStyle(.accessoryBar)
            .help("Watchtower needs Accessibility permission to focus editor windows")

        } else if let window = store.resolvedWindow(for: session) {
            Button {
                store.focus(session)
            } label: {
                label(icon: "arrow.up.forward.app.fill")
            }
            .buttonStyle(.accessoryBar)
            .help("Focus “\(window.title)” in \(window.appName)")
            .contextMenu { windowPicker }

        } else {
            Menu {
                windowPicker
            } label: {
                label(icon: "arrow.up.forward.app")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pick the editor window for this session")
        }
    }

    @ViewBuilder
    private var windowPicker: some View {
        if store.editorWindows.isEmpty {
            Text("No editor windows found")
        } else {
            Picker("Link to window", selection: selection) {
                Text("Not linked").tag(String?.none)
                ForEach(store.editorWindows) { window in
                    Text("\(window.title)  —  \(window.appName)")
                        .tag(Optional(window.id))
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.resolvedWindow(for: session)?.id },
            set: { newValue in
                guard let id = newValue,
                      let window = store.editorWindows.first(where: { $0.id == id })
                else {
                    store.unbind(session)
                    return
                }
                store.bind(session, to: window)
            }
        )
    }

    private func label(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9.5))
    }
}
