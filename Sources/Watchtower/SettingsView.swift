import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
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
                Text("Adds a count of working and waiting sessions to the menu bar, with a jump-to menu.")
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
