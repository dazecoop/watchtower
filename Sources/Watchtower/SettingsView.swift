import SwiftUI

/// The settings window's left-hand sections.
///
/// Everything about the notch used to sit on one tab, which ran to six
/// sections and needed scrolling to reach the end. The notch's shape and what
/// it does when you click it are separate decisions, so they get separate
/// pages rather than one long column.
private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance, notch, expanding, behaviour

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .notch: return "Notch"
        case .expanding: return "Expanding"
        case .behaviour: return "Behaviour"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette"
        case .notch: return "rectangle.topthird.inset.filled"
        case .expanding: return "arrow.up.left.and.arrow.down.right"
        case .behaviour: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: FleetStore

    @State private var page: SettingsPage = .appearance

    var body: some View {
        // Pinned open: there are four pages and no reason to ever hide them,
        // so the sidebar stays and its toggle button goes.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.label, systemImage: item.symbol)
                    .padding(.vertical, 5)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 176, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch page {
                case .appearance: AppearanceSettings()
                case .notch: NotchSettings()
                case .expanding: ExpandingSettings()
                case .behaviour: BehaviourSettings()
                }
            }
            .formStyle(.grouped)
            // Rows run the full width of whatever they are given, and across
            // a detail pane this wide that leaves a toggle's switch stranded
            // half a window away from its label.
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .top)
            // The title bar is dead space here — the sidebar already says
            // which page you are on, and the toolbar it sits in is twice the
            // height of an ordinary one.
            .toolbar(.hidden, for: .windowToolbar)
        }
        .frame(width: 780, height: 560)
    }
}

// MARK: - Appearance

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
                Caption("Dynamic fits as many tiles as the window allows.")
            }

            Section("Tiles") {
                Toggle("Render markdown", isOn: $store.renderMarkdown)
                Caption("Shows **bold** and `code` as formatting instead of raw syntax.")
                Toggle("Show thinking indicator", isOn: $store.showThinking)
            }
        }
    }
}

// MARK: - Notch

private struct NotchSettings: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        Form {
            Section {
                Toggle("Show the notch", isOn: $store.showOverlay)
                Caption("An always-on-top readout pinned to a screen edge: what's working, what's waiting on you, and your plan usage.")
            }

            Section("Position") {
                Picker("Edge", selection: $store.overlayEdge) {
                    ForEach(OverlayEdge.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Slider(value: $store.overlayOffset, in: 0...1) {
                    Text("Along the edge")
                } minimumValueLabel: {
                    Caption(store.overlayEdge.ends.start)
                } maximumValueLabel: {
                    Caption(store.overlayEdge.ends.end)
                }

                Caption("You can also drag the notch itself along its edge.")
            }
            .disabled(!store.showOverlay)

            Section("Shape") {
                Slider(value: $store.overlayScale, in: 0.6...2) {
                    Text("Size")
                } minimumValueLabel: {
                    Caption("Small")
                } maximumValueLabel: {
                    Caption("Large")
                }

                Slider(value: $store.overlayRounding, in: 0...60) {
                    Text("Rounding")
                } minimumValueLabel: {
                    Caption("Flat")
                } maximumValueLabel: {
                    Caption("Round")
                }

                Toggle("Sweep out of the screen edge", isOn: $store.overlaySweep)
                Caption("An end that reaches a screen corner sweeps into the second edge instead.")
            }
            .disabled(!store.showOverlay)
        }
    }
}

// MARK: - Expanding

private struct ExpandingSettings: View {
    @EnvironmentObject var store: FleetStore

    private var off: Bool { !store.showOverlay || !store.overlayExpands }

    var body: some View {
        Form {
            // Everything on this page describes what the notch does when you
            // reach for it, so with the notch off there is nothing here to
            // set. The page stays rather than vanishing from the sidebar —
            // going looking for a section that isn't there is worse than
            // finding it and being told why it's inert.
            if !store.showOverlay {
                Section {
                    Label("The notch is off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Caption("Expanding is what the notch does when you click or hover it, so none of this applies until the notch is showing.")
                    Button("Turn the notch on") { store.showOverlay = true }
                }
            }

            Section {
                Toggle("Expand the notch in place", isOn: $store.overlayExpands)
                    .disabled(!store.showOverlay)
                Caption("The notch swells open where it sits instead of bringing the window forward, and closes again once the pointer leaves it.")
            }
            .disabled(!store.showOverlay)

            Section("Opens on") {
                Picker("Opens on", selection: $store.overlayExpandTrigger) {
                    ForEach(OverlayExpandTrigger.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.overlayExpandTrigger == .hover {
                    Slider(value: $store.overlayHoverDelay, in: 0...1) {
                        Text("Delay")
                    } minimumValueLabel: {
                        Caption("Instant")
                    } maximumValueLabel: {
                        Caption("1s")
                    }

                    Caption(store.overlayHoverDelay < 0.05
                            ? "Opens the moment the pointer reaches the notch."
                            : String(format: "Opens after the pointer rests on the notch for %.2fs.",
                                     store.overlayHoverDelay))
                }
            }
            .disabled(off)

            Section("Opens into") {
                Picker("Opens into", selection: $store.overlayExpandStyle) {
                    ForEach(OverlayExpandStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Caption(store.overlayExpandStyle == .app
                        ? "The whole grid inside the notch, with a cog for Settings instead of a way back to the window. Clicks inside go to the app, so it closes by moving away."
                        : "A line per session and your plan usage. Click it anywhere to close, or Open to bring the window forward.")

                if store.overlayExpandStyle == .app {
                    Caption("Full app always draws on the notch's black rather than your theme — anything lighter reads as a window sitting in the bezel.")
                }
            }
            .disabled(off)
        }
    }
}

// MARK: - Behaviour

private struct BehaviourSettings: View {
    @EnvironmentObject var store: FleetStore
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Notify when a session needs you", isOn: $store.notifyOnAttention)
                Caption("Posts a notification the moment a session stops working and starts waiting on your reply.")
            }

            Section("Menu bar") {
                Toggle("Show menu bar status", isOn: $showMenuBarExtra)
                    .onChange(of: showMenuBarExtra) { _, _ in store.applyActivationPolicy() }
                Caption("Adds a count of working and waiting sessions to the menu bar, with a jump-to menu.")
            }

            Section("Dock") {
                Toggle("Hide Dock icon", isOn: $store.hideDockIcon)
                    .disabled(!store.canHideDockIcon)
                Caption(store.canHideDockIcon
                        ? "Runs Watchtower in the background, with no Dock icon and no app menu. Open it from the notch or the menu bar."
                        : "Turn on the notch or the menu bar status first. Hiding the Dock icon also hides the app menu, so without one of those there would be no way left to open Watchtower.")
            }

            Section("Editor windows") {
                if store.axTrusted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                } else {
                    HStack {
                        Caption("Accessibility access is needed to focus editor windows.")
                        Spacer()
                        Button("Grant…") { store.requestAccessibility() }
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// The explanatory line under a control. There were enough of these written
/// out by hand that they had started to disagree about size and colour.
private struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(.init(text))
            .font(.caption)
            .foregroundStyle(.secondary)
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
