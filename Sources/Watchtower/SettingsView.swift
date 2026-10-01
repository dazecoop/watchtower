import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            OverlaySettings()
                .tabItem { Label("Overlay", systemImage: "rectangle.topthird.inset.filled") }
            BehaviourSettings()
                .tabItem { Label("Behaviour", systemImage: "gearshape") }
        }
        .frame(width: 480)
        .padding(.top, 6)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject var store: FleetStore

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 180), spacing: 10)]

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Theme.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: store.theme == theme) {
                            store.theme = theme
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                Picker("Columns", selection: $store.columnCount) {
                    Text("Dynamic").tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Dynamic fits as many tiles as the window allows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tiles") {
                Toggle("Render markdown", isOn: $store.renderMarkdown)
                Text("Shows **bold** and `code` as formatting instead of raw syntax.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show thinking indicator", isOn: $store.showThinking)
            }
        }
        .formStyle(.grouped)
    }
}

private struct OverlaySettings: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        Form {
            Section("Floating overlay") {
                Toggle("Show overlay", isOn: $store.showOverlay)
                Text("A small always-on-top readout pinned to a screen edge, showing working and waiting counts, plan usage and the current activity. Click it to bring Watchtower forward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Position") {
                Picker("Edge", selection: $store.overlayEdge) {
                    ForEach(OverlayEdge.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Text(store.overlayEdge.ends.start)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $store.overlayOffset, in: 0...1)
                    Text(store.overlayEdge.ends.end)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("You can also drag the overlay itself to slide it along its edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!store.showOverlay)

            Section("Size") {
                HStack(spacing: 8) {
                    Text("Small")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $store.overlayScale, in: 0.6...2)
                    Text("Large")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!store.showOverlay)

            Section("Rounding") {
                Toggle("Sweep out of the screen edge", isOn: $store.overlaySweep)
                HStack(spacing: 8) {
                    Text("Flat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $store.overlayRounding, in: 0...60)
                    Text("Round")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Sets how far the notch sweeps out of the screen edge and how much its inner corners are rounded. An end that reaches a screen corner sweeps into the second edge instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!store.showOverlay)
        }
        .formStyle(.grouped)
    }
}

private struct BehaviourSettings: View {
    @EnvironmentObject var store: FleetStore
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Notify when a session needs you", isOn: $store.notifyOnAttention)
                Text("Posts a notification the moment a session stops working and starts waiting on your reply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show menu bar status", isOn: $showMenuBarExtra)
                    .onChange(of: showMenuBarExtra) { _, _ in store.applyActivationPolicy() }
                Text("Adds a count of working and waiting sessions to the menu bar, with a jump-to menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock") {
                Toggle("Hide Dock icon", isOn: $store.hideDockIcon)
                    .disabled(!store.canHideDockIcon)
                Text(store.canHideDockIcon
                     ? "Runs Watchtower in the background, with no Dock icon and no app menu. Open it from the notch or the menu bar."
                     : "Turn on the notch or the menu bar status first. Hiding the Dock icon also hides the app menu, so without one of those there would be no way left to open Watchtower.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Editor windows") {
                if store.axTrusted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                } else {
                    HStack {
                        Text("Accessibility access is needed to focus editor windows.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant…") { store.requestAccessibility() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.preview.window)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.preview.card)
                        .frame(height: 16)
                        .padding(.horizontal, 7)
                        .padding(.top, 9)
                }
                .frame(height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2 : 1)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.label)
                        .font(.system(size: 11, weight: .medium))
                    Text(theme.blurb)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
