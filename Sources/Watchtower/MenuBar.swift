import SwiftUI
import AppKit
import Combine

/// Owns the real `NSStatusItem`. Built in AppKit rather than as a SwiftUI
/// `MenuBarExtra` so the icon can be a composed, full-colour glyph (counts,
/// the network dot, the awake cup) instead of plain text, and so clicking it
/// opens an `NSPopover` — which draws its own arrow against the status item,
/// rather than either a plain `NSMenu` or the notch's Dynamic-Island-style
/// morph.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var store: FleetStore?
    private var watch: AnyCancellable?
    private var defaultsWatch: Any?
    private var appearanceWatch: NSKeyValueObservation?

    func attach(to store: FleetStore) {
        guard self.store == nil else { return }
        self.store = store

        // objectWillChange fires *before* the value lands, so read it a hop later.
        watch = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }

        // The "Show menu bar status" toggle lives in Settings as a plain
        // AppStorage bool, not a store property — watch defaults directly
        // rather than threading it through the store.
        defaultsWatch = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }

        appearanceWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.renderIcon() }
        }

        sync()
    }

    private func sync() {
        guard let store else { return }
        let wanted = UserDefaults.standard.bool(forKey: "showMenuBarExtra")
        if wanted, statusItem == nil {
            install()
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            popover = nil
        }
        if wanted { renderIcon() }
        _ = store // silence unused-binding warning when the branch above doesn't touch it
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageOnly
        statusItem = item
    }

    private func renderIcon() {
        guard let store, let button = statusItem?.button else { return }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let view = MenuBarIconView(
            working: store.workingCount,
            usageLimits: store.usage?.limits ?? [],
            netStatus: store.checkInternet ? store.netStatus : nil,
            awakeHeld: store.keepAwake ? store.isHoldingAwake : nil
        )
        .environment(\.colorScheme, isDark ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = false
        button.image = image
    }

    @objc private func togglePopover() {
        guard let store, let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let pop = popover ?? makePopover(store)
        popover = pop
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func makePopover(_ store: FleetStore) -> NSPopover {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
                .environmentObject(store)
        )
        return pop
    }
}

/// The status item's icon: the working count (or a moon when nothing's
/// active), three hairline usage bars, and — only when the matching setting
/// is on — a network dot and an awake cup. Rendered off-screen with
/// `ImageRenderer` and handed to the button as a plain `NSImage`, since the
/// button itself needs to stay a normal click target rather than a hosted
/// live view.
private struct MenuBarIconView: View {
    let working: Int
    let usageLimits: [UsageLimit]
    let netStatus: NetStatus?
    let awakeHeld: Bool?

    var body: some View {
        HStack(spacing: 4) {
            primary
            if !usageLimits.isEmpty {
                usageBars
            }
            if let netStatus {
                NetDot(status: netStatus, size: 5)
            }
            if let awakeHeld {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(awakeHeld ? Color.workingGreen : Color.dormantGray)
            }
        }
        .padding(.horizontal, 1)
        .fixedSize()
    }

    /// The working count when something's active; a moon once it's all quiet,
    /// since a waiting count in the icon itself was more noise than signal.
    @ViewBuilder
    private var primary: some View {
        if working > 0 {
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.workingGreen)
                Text("\(working)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
        } else {
            Image(systemName: "moon.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dormantGray)
        }
    }

    private var usageBars: some View {
        VStack(spacing: 1.5) {
            ForEach(Array(usageLimits.prefix(3).enumerated()), id: \.offset) { index, limit in
                MenuBarUsageHairline(percent: limit.expired ? 0 : limit.percent, color: .forLimit(index))
            }
        }
    }
}

/// One hairline track per plan limit: the same colour vocabulary as the
/// notch's rings (`Color.forLimit`), just flattened to a bar since there's no
/// room for an arc at menu-bar size. Also reused, wider, in the popover's
/// usage rows so the icon and the expanded view read as the same meter.
struct MenuBarUsageHairline: View {
    let percent: Int
    let color: Color
    var width: CGFloat = 12
    var height: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.15))
            Capsule().fill(color)
                .frame(width: width * CGFloat(min(max(percent, 0), 100)) / 100)
        }
        .frame(width: width, height: height)
    }
}
