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
            reposition()
        } else {
            hide()
        }
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
        let limits = (store.usage?.limits.prefix(3) ?? []).map { "\($0.shortLabel)\($0.percent)" }
        return [
            store.overlayEdge.rawValue,
            String(format: "%.2f", store.overlayScale),
            String(format: "%.1f", store.overlayRounding),
            "\(store.overlaySweep)",
            "\(store.overlayFlushStart)\(store.overlayFlushEnd)",
            limits.joined(separator: ","),
            "\(store.workingCount)/\(store.waitingCount)/\(store.sessions.count)"
        ].joined(separator: "|")
    }

    /// Re-fits the panel to its content, then parks it on the chosen edge.
    private func reposition() {
        guard let panel, let host, let store, let screen else { return }

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
        appliedFrame = target

        // Implicit animation here turns a one-off move into a visible slide.
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
