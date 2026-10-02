import AppKit
import SwiftUI
import Combine

// MARK: - Placement

enum OverlayEdge: String, CaseIterable, Identifiable {
    case top, bottom, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    /// Top and bottom lay their contents out in a row; the sides stack.
    var isHorizontal: Bool { self == .top || self == .bottom }

    /// Labels for the two ends of the position slider.
    var ends: (start: String, end: String) {
        isHorizontal ? ("Left", "Right") : ("Top", "Bottom")
    }

    /// The side of the panel that faces into the screen, where the corner
    /// sweep needs room to land.
    var inward: SwiftUI.Edge.Set {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .left: return .trailing
        case .right: return .leading
        }
    }
}

/// Maps an edge plus a 0…1 position into a screen rectangle, and back again
/// while dragging.
///
/// Anchored to the *physical* screen edge rather than `visibleFrame`, so
/// showing or hiding the Dock doesn't shunt the overlay sideways. The one
/// exception is the top, which sits under the menu bar instead of over it.
enum OverlayPlacement {
    /// Flush: the overlay is meant to grow out of the screen edge, so there is
    /// no gap to leave. `NotchShape` squares off the two corners that sit on
    /// the edge to match.
    static let margin: CGFloat = 0

    /// The highest the overlay may sit: the screen top, less the menu bar on
    /// whichever screen is showing one.
    static func usableTop(_ screen: NSScreen) -> CGFloat { bounds(screen).top }

    private static func bounds(_ screen: NSScreen) -> (full: CGRect, top: CGFloat) {
        let full = screen.frame
        // Zero on a screen that isn't showing the menu bar.
        let menuBar = full.maxY - screen.visibleFrame.maxY
        return (full, full.maxY - menuBar)
    }

    /// How far the overlay can travel along its edge.
    private static func span(size: CGSize, edge: OverlayEdge, screen: NSScreen) -> (origin: CGFloat, length: CGFloat) {
        let (full, top) = bounds(screen)
        if edge.isHorizontal {
            return (full.minX + margin, max(0, full.width - size.width - margin * 2))
        }
        // Vertical edges run downwards, so 0 reads as "top".
        let highest = top - margin - size.height
        return (highest, max(0, (top - margin) - (full.minY + margin) - size.height))
    }

    static func frame(size: CGSize, edge: OverlayEdge, offset: Double, screen: NSScreen) -> CGRect {
        let (full, top) = bounds(screen)
        let travel = span(size: size, edge: edge, screen: screen)
        let t = CGFloat(min(1, max(0, offset)))

        var origin = CGPoint.zero
        switch edge {
        case .top:
            origin = CGPoint(x: travel.origin + travel.length * t, y: top - size.height - margin)
        case .bottom:
            origin = CGPoint(x: travel.origin + travel.length * t, y: full.minY + margin)
        case .left:
            origin = CGPoint(x: full.minX + margin, y: travel.origin - travel.length * t)
        case .right:
            origin = CGPoint(x: full.maxX - size.width - margin, y: travel.origin - travel.length * t)
        }
        return CGRect(origin: origin, size: size)
    }

    /// Where the notch's centre sits along its edge, in screen coordinates.
    /// The open panel grows about this point, so it reads as coming out of the
    /// notch wherever the notch happens to be parked.
    static func anchor(of frame: CGRect, edge: OverlayEdge) -> CGFloat {
        edge.isHorizontal ? frame.midX : frame.midY
    }

    /// Frame for a panel of `size` swelling out of a notch centred on `anchor`.
    /// It grows symmetrically about that point, then slides back onto the
    /// screen if an end would overhang — a notch parked in a corner opens
    /// along the screen rather than off it.
    static func frame(size: CGSize, edge: OverlayEdge, anchoredAt anchor: CGFloat, screen: NSScreen) -> CGRect {
        let (full, top) = bounds(screen)
        let origin: CGPoint

        if edge.isHorizontal {
            let room = max(full.minX, full.maxX - size.width)
            let x = min(max(anchor - size.width / 2, full.minX), room)
            origin = CGPoint(x: x, y: edge == .top ? top - size.height : full.minY)
        } else {
            // Vertical edges are measured from the top down, so clamp the
            // panel's upper edge between the usable top and the screen floor.
            let highest = top
            let lowest = max(full.minY + size.height, highest - max(0, (highest - full.minY) - size.height) - size.height)
            let maxY = min(max(anchor + size.height / 2, min(lowest, highest)), highest)
            origin = CGPoint(x: edge == .left ? full.minX : full.maxX - size.width,
                             y: maxY - size.height)
        }
        return CGRect(origin: origin, size: size)
    }

    /// The inverse, for dragging: which position puts the overlay's leading
    /// corner at `value` along the edge.
    static func offset(forOrigin value: CGFloat, size: CGSize, edge: OverlayEdge, screen: NSScreen) -> Double {
        let travel = span(size: size, edge: edge, screen: screen)
        guard travel.length > 0 else { return 0 }
        let t = edge.isHorizontal
            ? (value - travel.origin) / travel.length
            : (travel.origin - value) / travel.length
        return Double(min(1, max(0, t)))
    }
}

/// SwiftUI's `openWindow` action, parked where AppKit code can reach it.
///
/// Rebuilding a closed `WindowGroup` window is something only SwiftUI can do:
/// `applicationShouldHandleReopen` is what a Dock click runs, but it does not
/// bring the scene back here, so clicking the notch after closing the window
/// did nothing. `RootView` stores the action while it is alive and it keeps
/// working once the window has gone.
@MainActor
enum AppWindow {
    static let id = "main"
    static var reopen: (() -> Void)?
}

// MARK: - Panel

/// Never becomes key or main: the overlay is a readout, and taking focus from
/// whatever you're typing in to show a usage percentage would be rude.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating overlay panel: builds it on demand, keeps it parked on the
/// chosen edge, and tears it down when switched off.
@MainActor
final class OverlayController: ObservableObject {
    private var panel: OverlayPanel?
    private var host: NSHostingView<AnyView>?
    private var store: FleetStore?
    private var watch: AnyCancellable?
    private var screenWatch: Any?

    /// Distance between the pointer and the panel's leading corner, captured
    /// when a drag starts so the overlay doesn't jump under the cursor.
    private var dragGrab: CGFloat?

    // MARK: Expansion

    /// Target state: what the content springs towards.
    @Published private(set) var expanded = false
    /// Whether the panel is currently holding the open size. It outlasts
    /// `expanded` on the way closed, so the shape has somewhere to shrink
    /// *into* instead of being clipped by a panel that already gave the
    /// space back.
    @Published private(set) var inflated = false

    /// Published so the content can lay itself out against the real panel
    /// rather than guessing: the open panel's size, and how far along the
    /// edge the collapsed notch's centre sits inside it.
    @Published private(set) var panelSize: CGSize = .zero
    @Published private(set) var anchorAlong: CGFloat = 0
    @Published private(set) var collapsedSize: CGSize = .zero

    private var deflate: DispatchWorkItem?
    private var settingsRaise: Timer?
    private var pointerWatch: Timer?
    private var awaySince: Date?
    private var overSince: Date?

    func attach(to store: FleetStore) {
        guard self.store == nil else { return }
        self.store = store

        // objectWillChange fires *before* the value lands, so read it a hop later.
        watch = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }

        screenWatch = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }

        sync()
    }

    // MARK: Lifecycle

    func sync() {
        guard let store else { return }
        if store.showOverlay {
            show(store)
            // Turning the swell off underneath an open panel would otherwise
            // strand it at the open size with no way back.
            if expanded && !store.overlayExpands { collapse() }
            reposition()
            syncPointerWatch()
        } else {
            hide()
        }
    }

    // MARK: Expand / collapse

    /// What a click on the notch does when the swell is switched on.
    func toggleExpanded() {
        expanded ? collapse() : expand()
    }

    func expand() {
        guard !expanded,
              let store, store.overlayExpands,
              let panel, let screen else { return }

        let collapsed = measuredSize ?? panel.frame.size
        let anchor = OverlayPlacement.anchor(of: panel.frame, edge: store.overlayEdge)

        // The summary is measured so it can't come up a row short; the full
        // app scrolls, so it is simply given a generous slice of the screen.
        let content = store.overlayExpandStyle == .app
            ? OverlayExpansion.appSize(screen: screen)
            : OverlayExpansion.contentSize(store: store)

        // Room at each end for the fillets the notch sweeps out of, matching
        // the padding the content view sets aside for them.
        let metrics = OverlayMetrics(scale: CGFloat(store.overlayScale),
                                     rounding: CGFloat(store.overlayRounding),
                                     sweep: store.overlaySweep)
        let ends = metrics.flare * 2
        // An end parked in a screen corner sweeps into the perpendicular edge
        // instead, which costs depth rather than length. The shape gives that
        // strip up either way, so the panel has to be that much deeper or the
        // last row lands underneath it.
        let sweep = (store.overlayFlushStart || store.overlayFlushEnd) ? metrics.flare : 0

        // The summary is authored at a fixed width running into the screen, so
        // on a side edge that width becomes the panel's depth. The full app is
        // authored at both dimensions and keeps them whichever edge it is on.
        let along = store.overlayEdge.isHorizontal ? content.width : content.height
        let depth = store.overlayEdge.isHorizontal ? content.height : content.width

        let size = store.overlayEdge.isHorizontal
            ? CGSize(width: max(along + ends, collapsed.width), height: depth + sweep)
            : CGSize(width: depth + sweep, height: max(along + ends, collapsed.height))

        let target = OverlayPlacement.frame(size: size,
                                            edge: store.overlayEdge,
                                            anchoredAt: anchor,
                                            screen: screen).integral

        collapsedSize = collapsed
        panelSize = target.size
        anchorAlong = store.overlayEdge.isHorizontal
            ? anchor - target.minX
            : target.maxY - anchor

        deflate?.cancel()
        // The panel takes the room first, with the content still drawn at the
        // collapsed size and sitting exactly where the notch already was, so
        // nothing jumps. The spring then runs inside a panel that is already
        // big enough to hold it.
        inflated = true
        apply(frame: target)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.inflated else { return }
            withAnimation(OverlayExpansion.spring) { self.expanded = true }
        }

        syncPointerWatch()
    }

    /// Watches where the pointer actually is, which drives both halves of the
    /// hover behaviour: resting on the notch opens it, and leaving the open
    /// panel closes it again.
    ///
    /// SwiftUI's `onHover` can't be trusted for either: the panel never
    /// becomes key, and swapping the collapsed body for the open one mid-
    /// gesture re-enters the hover state without the mouse having moved, which
    /// shut the panel the instant it opened. Asking the system for the pointer
    /// has no such ambiguity.
    ///
    /// It runs while the panel is open, and while hover is the trigger and so
    /// something has to notice the pointer arriving.
    func syncPointerWatch() {
        let wanted = panel != nil
            && (expanded || (store?.overlayExpands == true
                             && store?.overlayExpandTrigger == .hover))
        guard wanted else { return stopPointerWatch() }
        guard pointerWatch == nil else { return }

        // Fine-grained, because the hover delay can be set to zero and a
        // coarse timer would make "instant" feel like a quarter second.
        pointerWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointer() }
        }
    }

    private func stopPointerWatch() {
        pointerWatch?.invalidate()
        pointerWatch = nil
        awaySince = nil
        overSince = nil
    }

    private func checkPointer() {
        guard let panel, let store else { return stopPointerWatch() }

        // A little slack around the edge, so grazing the boundary on the way
        // to a row doesn't count as leaving.
        let inside = panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)

        if expanded {
            overSince = nil
            if inside {
                awaySince = nil
            } else if let since = awaySince {
                if Date().timeIntervalSince(since) > 0.4 { collapse() }
            } else {
                awaySince = Date()
            }
            return
        }

        // Collapsed, and hover is what opens it.
        awaySince = nil
        guard store.overlayExpands, store.overlayExpandTrigger == .hover else {
            overSince = nil
            return
        }

        guard inside else {
            overSince = nil
            return
        }
        let since = overSince ?? Date()
        overSince = since
        if Date().timeIntervalSince(since) >= store.overlayHoverDelay { expand() }
    }

    /// Brings the Settings window to wherever you are.
    ///
    /// SwiftUI restores it to wherever it was last left, so with several
    /// Spaces it opens on a different desktop, or behind what you are looking
    /// at, or on a display that has since been unplugged. That is survivable
    /// from the main window — there is a Dock icon and a menu to go find it —
    /// but not from the notch in full-app mode, where the whole point is that
    /// there is no window to go back to.
    func raiseSettings() {
        // `SettingsLink` opens the window some way down the line, and how far
        // depends on how much there is to build — guessing a delay meant the
        // sidebar's window appeared after the last guess had already run, and
        // opened behind whatever was in front. Watch for it instead, and stop
        // as soon as it is up.
        settingsRaise?.invalidate()
        let deadline = Date().addingTimeInterval(3)
        settingsRaise = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return timer.invalidate() }
                if self.bringSettingsForward() || Date() > deadline { timer.invalidate() }
            }
        }
    }

    @discardableResult
    private func bringSettingsForward() -> Bool {
        guard let window = NSApp.windows.first(where: {
            ($0.identifier?.rawValue ?? "").contains("SwiftUI_Settings") && $0.isVisible
        }) else { return false }

        // Have it follow you to this desktop, rather than Spaces switching
        // out from under you to go to it.
        window.collectionBehavior.insert(.moveToActiveSpace)

        // A frame saved against a display that is no longer attached leaves it
        // parked off the edge of everything.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }

        // Asking to be activated is not enough on its own. The click that got
        // us here landed on a panel that refuses to activate the app, so macOS
        // declines to hand over the foreground and the window opens behind
        // whatever you were using. Ordering it front at a floating level puts
        // it where it belongs regardless, and dropping back to normal a moment
        // later leaves it at the front of the ordinary stack rather than
        // hovering over everything for the rest of the session.
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            window.level = .normal
        }
        return true
    }


    /// `animated: false` shuts the panel in one step instead of springing it.
    ///
    /// Used when something else is about to appear in the same place: the
    /// Settings window opens the instant the cog is clicked, and the notch
    /// panel sits above it, so springing the panel closed over the next half
    /// second left Settings arriving underneath a notch still on its way out.
    /// Snapping shut first gets the order right — panel gone, then Settings.
    func collapse(animated: Bool = true) {
        guard expanded else { return }
        stopPointerWatch()
        deflate?.cancel()

        guard animated else {
            expanded = false
            inflated = false
            measuredFor = nil
            appliedFrame = nil
            reposition()
            syncPointerWatch()
            return
        }

        withAnimation(OverlayExpansion.spring) { expanded = false }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.expanded else { return }
            self.inflated = false
            // Hover mode still needs a watcher once the panel is shut.
            self.syncPointerWatch()
            // Re-fit to the collapsed body and park it back on its edge.
            self.measuredFor = nil
            self.appliedFrame = nil
            self.reposition()
        }
        deflate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OverlayExpansion.settle, execute: work)
    }

    private func show(_ store: FleetStore) {
        if panel != nil { return }

        let content = AnyView(
            OverlayContent(controller: self)
                .environmentObject(store)
                .environment(\.theme, store.theme)
                .environment(\.renderMarkdown, store.renderMarkdown)
                // The overlay is on screen whenever it exists, so its timers
                // and animations always run.
                .environment(\.liveTicking, true)
        )

        let host = NSHostingView(rootView: content)
        // Needed to measure the content; the panel is then sized to match.
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]

        let panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 420, height: 40)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        // Above ordinary windows and over full-screen apps, and it follows you
        // between Spaces rather than living on the one it was created on.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.orderFrontRegardless()

        self.panel = panel
        self.host = host
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        host = nil
        appliedFrame = nil
        measuredSize = nil
        measuredFor = nil
        deflate?.cancel()
        deflate = nil
        stopPointerWatch()
        expanded = false
        inflated = false
    }

    // MARK: Geometry

    private var screen: NSScreen? { panel?.screen ?? NSScreen.main ?? NSScreen.screens.first }

    /// The last frame we asked for, and the content signature it was measured
    /// against. Compared against our own request rather than `panel.frame`,
    /// which AppKit may hand back adjusted — that difference never resolves,
    /// so every tick would set the frame again and the overlay would crawl.
    private var appliedFrame: CGRect?
    private var measuredSize: CGSize?
    private var measuredFor: String?

    /// Everything that can change the overlay's measured size. The thinking
    /// word and its timer are deliberately absent: they live in a fixed-width
    /// column, so they must never re-measure the panel.
    private func signature(_ store: FleetStore) -> String {
        let limits = (store.usage?.limits.prefix(3) ?? []).map { "\($0.shortLabel)\($0.figure)" }
        return [
            store.overlayEdge.rawValue,
            String(format: "%.2f", store.overlayScale),
            String(format: "%.1f", store.overlayRounding),
            "\(store.overlaySweep)",
            "\(store.overlayFlushStart)\(store.overlayFlushEnd)",
            limits.joined(separator: ","),
            "\(store.workingCount)/\(store.waitingCount)/\(store.sessions.count)",
            // Cleaning up changes both the row count and the header's chips.
            "\(store.listed.count)/\(store.hasCleanedUp)/\(store.cleanableCount > 0)",
            // Each indicator the header gains is width the panel has to allow.
            "\(store.checkInternet)/\(store.keepAwake)"
        ].joined(separator: "|")
    }

    /// Re-fits the panel to its content, then parks it on the chosen edge.
    private func reposition() {
        // `apply(frame:)` owns the panel itself; this only works out where it
        // should go.
        guard let host, let store, let screen, panel != nil else { return }
        // While the panel is open its frame is the expansion's to own; fitting
        // it to the collapsed body would snap it shut mid-spring.
        guard !inflated else { return }

        let key = signature(store)
        if measuredFor != key || measuredSize == nil {
            host.layoutSubtreeIfNeeded()
            let fitted = host.fittingSize
            measuredSize = CGSize(
                width: min(max(fitted.width.rounded(.up), 28),
                           screen.frame.width),
                height: min(max(fitted.height.rounded(.up), 28), screen.frame.height / 2)
            )
            measuredFor = key
        }
        guard let size = measuredSize else { return }

        let target = OverlayPlacement.frame(size: size,
                                            edge: store.overlayEdge,
                                            offset: store.overlayOffset,
                                            screen: screen).integral

        // Squaring an end changes the content's padding, so the panel has to be
        // re-measured. Publishing the change re-enters here a hop later.
        let flush = flushEnds(frame: target, store: store, screen: screen)
        if flush.start != store.overlayFlushStart || flush.end != store.overlayFlushEnd {
            store.setOverlayFlush(start: flush.start, end: flush.end)
            return
        }

        guard target != appliedFrame else { return }
        apply(frame: target)
    }

    /// Moves the panel without any implicit animation — AppKit would otherwise
    /// turn a one-off reposition into a visible slide, and the swell is
    /// animated by SwiftUI inside the panel rather than by the window itself.
    private func apply(frame target: CGRect) {
        guard let panel, let host else { return }
        appliedFrame = target

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(target, display: true, animate: false)
        }

        // `sizingOptions` drives the hosting view off its intrinsic size, which
        // leaves it laying out against its own constraints rather than the
        // panel it now fills. Pinning the frame keeps the two in step.
        host.frame = CGRect(origin: .zero, size: target.size)
    }

    /// Whether either end of the notch has reached the screen corner. The two
    /// thresholds give it hysteresis: squaring an end shortens the panel and
    /// so nudges the measurement, and a single threshold would let that flip
    /// back and forth every frame.
    private func flushEnds(frame: CGRect, store: FleetStore, screen: NSScreen) -> (start: Bool, end: Bool) {
        let enter: CGFloat = 5
        let leave: CGFloat = 9
        let full = screen.frame

        let startGap: CGFloat
        let endGap: CGFloat
        if store.overlayEdge.isHorizontal {
            startGap = frame.minX - full.minX
            endGap = full.maxX - frame.maxX
        } else {
            // Offset zero is the top.
            startGap = OverlayPlacement.usableTop(screen) - frame.maxY
            endGap = frame.minY - full.minY
        }

        func settle(_ gap: CGFloat, was: Bool) -> Bool {
            was ? gap <= leave : gap <= enter
        }
        return (settle(startGap, was: store.overlayFlushStart),
                settle(endGap, was: store.overlayFlushEnd))
    }

    // MARK: Dragging

    func beginDrag() { dragGrab = nil }

    /// Driven from the content view with the global pointer location: the
    /// panel moves as we go, so gesture-relative translations would feed back
    /// on themselves.
    func drag(to mouse: CGPoint) {
        guard let panel, let store, let screen else { return }
        let edge = store.overlayEdge
        let frame = panel.frame

        if dragGrab == nil {
            dragGrab = edge.isHorizontal ? mouse.x - frame.minX : mouse.y - frame.minY
        }
        guard let grab = dragGrab else { return }

        let leading = (edge.isHorizontal ? mouse.x : mouse.y) - grab
        store.overlayOffset = OverlayPlacement.offset(forOrigin: leading,
                                                      size: frame.size,
                                                      edge: edge,
                                                      screen: screen)
    }

    func endDrag() { dragGrab = nil }

    // MARK: Click-through to the app

    /// Brings the main window forward, reopening it if it was closed.
    func revealApp() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow() {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Every window was closed, so ask SwiftUI for a fresh one.
        AppWindow.reopen?()

        // Restoring happens a run loop later, so bring it forward once it has.
        DispatchQueue.main.async { [weak self] in
            self?.mainWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    /// The app's own window, if one is actually on screen.
    ///
    /// `isVisible` matters: a closed `WindowGroup` window can linger in
    /// `NSApp.windows` as an off-screen husk, and treating that as the main
    /// window meant clicking the notch quietly did nothing instead of
    /// reopening the app.
    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard !(window is OverlayPanel), window.isVisible, window.canBecomeMain else { return false }
            // The Settings scene is also a main-capable window; skip it.
            return !(window.identifier?.rawValue ?? "").contains("Settings")
        }
    }
}
