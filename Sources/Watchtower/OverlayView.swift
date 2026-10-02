import SwiftUI

/// Every size derives from the chosen scale rather than being applied as a
/// `scaleEffect` over a fixed design — that would resample the text and leave
/// it soft.
struct OverlayMetrics {
    let scale: CGFloat
    /// The user's rounding, in points before scaling.
    let rounding: CGFloat
    /// Whether the notch sweeps out of the screen edge at all.
    let sweep: Bool

    var pad: CGFloat { round(7 * scale) }

    /// Concave radius where the notch meets the screen edge, so it swells out
    /// of the bezel and back again rather than butting against it.
    ///
    /// Capped at the notch's own depth: a fillet deeper than that has nowhere
    /// to land, and the shape would clamp it while the padding reserved for it
    /// kept growing, leaving dead space at each end.
    var flare: CGFloat {
        sweep ? min(round(rounding * scale), gauge + pad * 2) : 0
    }
    /// Convex radius on the two corners facing into the screen. Driven by the
    /// same control, a little tighter, so one slider shapes the whole outline.
    var corner: CGFloat { round(rounding * 0.8 * scale) }

    /// Outer diameter of the gauge. Everything else follows from it, and it
    /// has to clear three nested arcs plus the mark: too small and the
    /// innermost arc's stroke closes over its own centre, which reads as a
    /// filled disc rather than a gauge.
    var gauge: CGFloat { round(56 * scale) }
    var ring: CGFloat { max(2, round(2.5 * scale)) }
    var ringGap: CGFloat { max(1.5, round(2 * scale)) }

    /// The spinner sits inside every usage arc, and the mark inside that.
    var spinnerInset: CGFloat { round(15.5 * scale) }
    var spinner: CGFloat { max(1.5, round(2 * scale)) }
    var mark: CGFloat { round(19 * scale) }
    var percent: CGFloat { round(10 * scale) }
}

/// The notch outline: flush along the screen edge, swelling out of it through
/// a concave fillet at each end and rounding off on the two corners that face
/// into the screen — the MacBook notch profile.
///
/// Built once with the edge along the top, then rotated into place, so the
/// four edges can't drift apart. An earlier version assembled each edge from
/// tangent arcs by hand and produced an empty path for the sides, which
/// silently clipped the whole overlay away.
struct NotchShape: Shape {
    let edge: OverlayEdge
    let corner: CGFloat
    let flare: CGFloat
    /// Ends that have reached a screen corner, in edge space. Such an end is
    /// touching a second screen edge, so instead of sweeping back into the
    /// docked edge it sweeps out of that perpendicular one.
    var cornerStart = false
    var cornerEnd = false
    /// Depth reserved for a corner sweep to land in — the same padding the
    /// content view sets aside for it, so the two always agree.
    var cornerSweep: CGFloat = 0

    /// Control-point ratio that makes a cubic match a quarter circle.
    private static let kappa: CGFloat = 0.5523

    func path(in rect: CGRect) -> Path {
        let along = edge.isHorizontal ? rect.width : rect.height
        let depth = edge.isHorizontal ? rect.height : rect.width

        let transform = placement(in: rect)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return profile(along: along, depth: depth).applying(transform)
    }

    /// Maps the edge-along-the-top construction onto the requested edge.
    private func placement(in rect: CGRect) -> CGAffineTransform {
        switch edge {
        case .top:
            return .identity
        case .bottom:
            return CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: rect.height))
        case .left:
            return CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(translationX: 0, y: rect.height))
        case .right:
            return CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(translationX: rect.width, y: 0))
        }
    }

    /// A quarter turn from `from` to `to` bending around `pivot`. Used for both
    /// the convex corners and the concave fillets — only the pivot's side of
    /// the curve differs.
    private func turn(_ path: inout Path, from start: CGPoint, to end: CGPoint, pivot: CGPoint) {
        let k = Self.kappa
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + (pivot.x - start.x) * k,
                              y: start.y + (pivot.y - start.y) * k),
            control2: CGPoint(x: end.x + (pivot.x - end.x) * k,
                              y: end.y + (pivot.y - end.y) * k)
        )
    }

    private func profile(along: CGFloat, depth: CGFloat) -> Path {
        // The body stops short of the panel's full depth by whatever a corner
        // sweep needs; that strip is used only where one lands.
        let body = max(0, depth - cornerSweep)
        let limit = max(0, min(flare, along / 2 - 1, body))

        let startFlare = cornerStart ? 0 : limit
        let endFlare = cornerEnd ? 0 : limit

        let room = max(0, min((along - startFlare - endFlare) / 2, body - limit))
        let startCorner = cornerStart ? 0 : max(0, min(corner, room))
        let endCorner = cornerEnd ? 0 : max(0, min(corner, room))

        let far = along - endFlare

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))

        if cornerStart {
            // Hug the perpendicular screen edge, then sweep out of it. With no
            // sweep to make this degenerates to a square end on its own.
            path.addLine(to: CGPoint(x: 0, y: body + cornerSweep))
            turn(&path, from: CGPoint(x: 0, y: body + cornerSweep),
                 to: CGPoint(x: cornerSweep, y: body),
                 pivot: CGPoint(x: 0, y: body))
        } else {
            turn(&path, from: CGPoint(x: 0, y: 0), to: CGPoint(x: startFlare, y: startFlare),
                 pivot: CGPoint(x: startFlare, y: 0))
            path.addLine(to: CGPoint(x: startFlare, y: body - startCorner))
            turn(&path, from: CGPoint(x: startFlare, y: body - startCorner),
                 to: CGPoint(x: startFlare + startCorner, y: body),
                 pivot: CGPoint(x: startFlare, y: body))
        }

        if cornerEnd {
            path.addLine(to: CGPoint(x: far - cornerSweep, y: body))
            turn(&path, from: CGPoint(x: far - cornerSweep, y: body),
                 to: CGPoint(x: far, y: body + cornerSweep),
                 pivot: CGPoint(x: far, y: body))
            path.addLine(to: CGPoint(x: along, y: 0))
        } else {
            path.addLine(to: CGPoint(x: far - endCorner, y: body))
            turn(&path, from: CGPoint(x: far - endCorner, y: body),
                 to: CGPoint(x: far, y: body - endCorner),
                 pivot: CGPoint(x: far, y: body))
            path.addLine(to: CGPoint(x: far, y: endFlare))
            turn(&path, from: CGPoint(x: far, y: endFlare), to: CGPoint(x: along, y: 0),
                 pivot: CGPoint(x: far, y: 0))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Root

struct OverlayContent: View {
    @ObservedObject var controller: OverlayController

    @EnvironmentObject private var store: FleetStore

    @State private var hovering = false
    @State private var moved = false

    private var m: OverlayMetrics {
        OverlayMetrics(scale: CGFloat(store.overlayScale),
                       rounding: CGFloat(store.overlayRounding),
                       sweep: store.overlaySweep)
    }

    /// Three arcs is as many as stay apart at this size, and the limits past
    /// them are the least urgent.
    private var limits: [UsageLimit] {
        Array((store.usage?.limits ?? []).prefix(3))
    }

    /// The limit closest to biting, which is the number worth printing.
    /// Expired windows are skipped: their percentage is no longer the live one.
    private var headline: UsageLimit? {
        limits.filter { !$0.expired }.max { $0.percent < $1.percent }
    }

    /// Claude Code writes these figures only while it runs, so with nothing
    /// open they freeze. Fade the gauge rather than present them as current.
    private var usageStale: Bool { store.usage?.stale ?? false }

    private var fleet: FleetMood {
        if store.workingCount > 0 { return .working }
        if store.waitingCount > 0 { return .waiting }
        return .idle
    }

    var body: some View {
        Group {
            if controller.inflated {
                morphing
            } else {
                face()
            }
        }
        .onHover { hovering = $0 }
        .gesture(moveOrOpen)
        .help(controller.inflated ? "" : summary)
    }

    // MARK: Swell

    /// The notch and the open panel are the same black shape at two sizes.
    /// Rather than resize the window — which stutters, and clips whatever is
    /// mid-flight — the panel is already at the open size by the time this
    /// runs, and the shape springs between the two inside it.
    ///
    /// Everything is expressed along the edge and into the screen, then mapped
    /// onto x and y at the end, so one set of rules covers all four edges: the
    /// panel always grows out of the edge the notch is docked to, and about
    /// the point the notch was sitting at.
    private var morphing: some View {
        let panel = controller.panelSize
        let horizontal = store.overlayEdge.isHorizontal
        let open = controller.expanded

        let panelAlong = horizontal ? panel.width : panel.height
        let panelDepth = horizontal ? panel.height : panel.width
        let shutAlong = horizontal ? controller.collapsedSize.width : controller.collapsedSize.height
        let shutDepth = horizontal ? controller.collapsedSize.height : controller.collapsedSize.width

        let along = open ? panelAlong : shutAlong
        let depth = open ? panelDepth : shutDepth

        // Closed, the shape sits centred on where the notch was; open, it
        // fills the panel. A notch near a screen corner opens off-centre, and
        // the anchor is what keeps the two ends in step.
        let originAlong = open
            ? 0
            : min(max(controller.anchorAlong - along / 2, 0), max(0, panelAlong - along))
        // Bottom and right edges hang off the far side of the panel.
        let far = store.overlayEdge == .bottom || store.overlayEdge == .right
        let originDepth = far ? panelDepth - depth : 0

        return ZStack(alignment: .topLeading) {
            face(width: horizontal ? along : depth,
                 height: horizontal ? depth : along)
                .offset(x: horizontal ? originAlong : originDepth,
                        y: horizontal ? originDepth : originAlong)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
    }

    /// The black body itself. Collapsed it is the gauge; open it is the fleet,
    /// and the two cross-fade so neither ever has to squeeze into the other's
    /// size on the way through.
    ///
    /// The size has to be imposed on the stack *before* the background, or the
    /// shape fits itself to the gauge — which is fixed-size — and the swell
    /// leaves a notch-sized bezel floating in an open panel.
    /// What the notch opens into: a compact readout, or the whole grid.
    @ViewBuilder
    private var openBody: some View {
        if store.overlayExpandStyle == .app {
            // No way back to the window from here by design: the cog opens
            // Settings and the notch stays the app. The panel shuts itself
            // once the pointer leaves for the Settings window.
            ExpandedAppPanel(onSettings: {
                // A hop first: this gesture runs alongside the `SettingsLink`
                // it sits on, and collapsing without the delay tears the link
                // out of the view tree before its own action has run, so
                // Settings never opens at all. One turn of the run loop is
                // enough for the link to fire.
                //
                // Then shut in one step rather than springing, so the panel is
                // gone before the Settings window arrives underneath it.
                DispatchQueue.main.async {
                    controller.collapse(animated: false)
                    controller.raiseSettings()
                }
            })
        } else {
            ExpandedPanel(
                onOpenApp: {
                    controller.collapse()
                    controller.revealApp()
                },
                onPick: { session in
                    controller.collapse()
                    store.focus(session)
                }
            )
        }
    }

    /// The open content's own size: the panel less the fillets at each end,
    /// which belong to the shape rather than to the list.
    private var openSize: CGSize {
        let panel = controller.panelSize
        return store.overlayEdge.isHorizontal
            ? CGSize(width: max(0, panel.width - m.flare * 2),
                     height: max(0, panel.height - cornerSweep))
            : CGSize(width: max(0, panel.width - cornerSweep),
                     height: max(0, panel.height - m.flare * 2))
    }

    private func face(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        ZStack {
            collapsedFace
                .opacity(controller.expanded ? 0 : 1)

            if controller.inflated {
                openBody
                    .environmentObject(store)
                // Pinned to the size it will settle at, and clipped by the
                // shape on the way there. Left to fit the shape as it springs
                // it would re-wrap every frame, and the panel would arrive
                // through a blur of truncating names.
                .frame(width: openSize.width, height: openSize.height)
                // Keep clear of the strip the shape reserves for a corner
                // sweep, exactly as the collapsed face does.
                .padding(store.overlayEdge.inward, cornerSweep)
                .opacity(controller.expanded ? 1 : 0)
                .allowsHitTesting(controller.expanded)
            }
        }
        .frame(width: width, height: height)
        .background {
            // Pure black and unbordered, so it reads as bezel, not as a window.
            shape.fill(Color.black)
            shape.fill(Color.white.opacity(hovering && !controller.expanded ? 0.10 : 0))
        }
        .clipShape(shape)
        .contentShape(shape)
    }

    private var collapsedFace: some View {
        VStack(spacing: round(2 * m.scale)) {
            UsageGauge(limits: limits, mood: fleet, metrics: m, stale: usageStale)

            if let headline {
                Text("\(headline.percent)%")
                    .font(.system(size: m.percent, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.forSeverity(headline.level) ?? .white.opacity(0.92))
                    .monospacedDigit()
                    .opacity(usageStale ? 0.5 : 1)
            }
        }
        .fixedSize()
        .padding(m.pad)
        // Room for the fillets, which belong to the shape rather than to the
        // content. An end that has squared off needs none.
        .padding(store.overlayEdge.isHorizontal ? .leading : .top,
                 store.overlayFlushStart ? 0 : m.flare)
        .padding(store.overlayEdge.isHorizontal ? .trailing : .bottom,
                 store.overlayFlushEnd ? 0 : m.flare)
        // An end sitting in a screen corner sweeps into the perpendicular edge
        // instead, which needs depth rather than length.
        .padding(store.overlayEdge.inward, cornerSweep)
    }

    /// Depth set aside for a corner sweep, and zero when neither end is in a
    /// corner — the shape is handed the same number.
    private var cornerSweep: CGFloat {
        (store.overlayFlushStart || store.overlayFlushEnd) ? m.flare : 0
    }

    private var shape: NotchShape {
        // The flush flags are in offset terms, where 0 is the left of a
        // horizontal edge and the top of a vertical one. `NotchShape` works in
        // edge space, and the left edge's rotation reverses the two.
        let reversed = store.overlayEdge == .left
        return NotchShape(
            edge: store.overlayEdge,
            corner: m.corner,
            flare: m.flare,
            cornerStart: reversed ? store.overlayFlushEnd : store.overlayFlushStart,
            cornerEnd: reversed ? store.overlayFlushStart : store.overlayFlushEnd,
            cornerSweep: cornerSweep
        )
    }

    /// The detail that doesn't fit on the face of it. A tooltip costs no space
    /// and can't resize the panel.
    private var summary: String {
        var lines: [String] = []

        var counts: [String] = []
        if store.workingCount > 0 { counts.append("\(store.workingCount) working") }
        if store.waitingCount > 0 { counts.append("\(store.waitingCount) your turn") }
        lines.append(counts.isEmpty
                     ? "\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s"), all idle"
                     : counts.joined(separator: " · "))

        if !limits.isEmpty {
            let figures = limits
                .map { "\($0.label) \($0.figure)" }
                .joined(separator: " · ")
            lines.append(usageStale ? "\(figures) (not current)" : figures)
        }

        if let busy = store.sessions
            .filter({ $0.state != .dormant })
            .sorted(by: { $0.state == $1.state ? $0.lastActivity > $1.lastActivity : $0.state < $1.state })
            .first {
            let detail = busy.state == .working
                ? "working for \(shortDuration(Date().timeIntervalSince(busy.parsed.events.last?.at ?? busy.statusUpdatedAt)))"
                : busy.state.label.lowercased()
            lines.append("\(busy.name) — \(detail)")
        }

        lines.append("Click to open Watchtower · drag to move")
        return lines.joined(separator: "\n")
    }

    /// What a click on the notch itself does. Inside the open full app it does
    /// nothing: there you are clicking tiles, filters and the cog, and having
    /// the panel shut under every one of those would make it unusable. The
    /// summary is small enough that a click anywhere still closes it.
    private func tapped() {
        guard store.overlayExpands else { return controller.revealApp() }
        if controller.expanded && store.overlayExpandStyle == .app { return }
        controller.toggleExpanded()
    }

    /// One gesture covers both jobs: a press that never travels opens the app,
    /// anything further moves the overlay. Two separate gestures would race.
    private var moveOrOpen: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !moved {
                    guard !controller.expanded else { return }
                    guard hypot(value.translation.width, value.translation.height) > 3 else { return }
                    moved = true
                    controller.beginDrag()
                }
                controller.drag(to: NSEvent.mouseLocation)
            }
            .onEnded { _ in
                if !moved { tapped() }
                controller.endDrag()
                moved = false
            }
    }
}

enum FleetMood {
    case working, waiting, idle
}

// MARK: - Gauge

/// Concentric arcs, one per plan limit, around a mark that reports what the
/// fleet is doing: spinning while a session is mid-turn, breathing amber when
/// one is waiting on you, still when everything is idle.
private struct UsageGauge: View {
    let limits: [UsageLimit]
    let mood: FleetMood
    let metrics: OverlayMetrics

    /// Nothing has refreshed the figures in a while.
    var stale = false

    var body: some View {
        ZStack {
            ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                arc(limit, index: index, inset: CGFloat(index) * (metrics.ring + metrics.ringGap))
            }

            if limits.isEmpty {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: metrics.ring)
            }

            tracker
            mark
        }
        .frame(width: metrics.gauge, height: metrics.gauge)
    }

    private func arc(_ limit: UsageLimit, index: Int, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.11), lineWidth: metrics.ring)
            Circle()
                .inset(by: metrics.ring / 2)
                // An expired window's figure describes a window that has
                // already rolled over, so draw no arc for it at all.
                .trim(from: 0, to: limit.expired ? 0 : min(1, Double(limit.percent) / 100))
                .stroke(Color.forLimit(index),
                        style: StrokeStyle(lineWidth: metrics.ring, lineCap: .round))
                // Trims start at three o'clock; usage reads better from the top.
                .rotationEffect(.degrees(-90))
                .opacity(stale ? 0.45 : 1)
                .animation(.easeOut(duration: 0.5), value: limit.expired ? 0 : limit.percent)
        }
        .padding(inset)
    }

    /// Sits still, and stays white. Anything moving or flashing in the middle
    /// of the gauge reads as the whole overlay moving, which is the opposite
    /// of a readout you can ignore until it matters. The spinner alone says
    /// when something is running.
    @ViewBuilder
    private var mark: some View {
        ClaudeMark()
            .fill(Color.white)
            .frame(width: metrics.mark, height: metrics.mark)
    }

    /// A thin arc tracking inside the gauge while a session is mid-turn — the
    /// one moving part, and only when something is actually happening.
    @ViewBuilder
    private var tracker: some View {
        if mood == .working {
            // Core Animation, not a SwiftUI rotation — see `Animations.swift`.
            SpinnerArc(lineWidth: metrics.spinner)
                .padding(metrics.spinnerInset)
        }
    }
}
