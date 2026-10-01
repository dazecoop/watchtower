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
    let controller: OverlayController

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
    private var headline: UsageLimit? {
        limits.max { $0.percent < $1.percent }
    }

    private var fleet: FleetMood {
        if store.workingCount > 0 { return .working }
        if store.waitingCount > 0 { return .waiting }
        return .idle
    }

    var body: some View {
        VStack(spacing: round(2 * m.scale)) {
            UsageGauge(limits: limits, mood: fleet, metrics: m)

            if let headline {
                Text("\(headline.percent)%")
                    .font(.system(size: m.percent, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.forSeverity(headline.level) ?? .white.opacity(0.92))
                    .monospacedDigit()
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
        .background {
            // Pure black and unbordered, so it reads as bezel, not as a window.
            shape.fill(Color.black)
            shape.fill(Color.white.opacity(hovering ? 0.10 : 0))
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .gesture(moveOrOpen)
        .help(summary)
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
            lines.append(limits.map { "\($0.label) \($0.percent)%" }.joined(separator: " · "))
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

    /// One gesture covers both jobs: a press that never travels opens the app,
    /// anything further moves the overlay. Two separate gestures would race.
    private var moveOrOpen: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !moved {
                    guard hypot(value.translation.width, value.translation.height) > 3 else { return }
                    moved = true
                    controller.beginDrag()
                }
                controller.drag(to: NSEvent.mouseLocation)
            }
            .onEnded { _ in
                if !moved { controller.revealApp() }
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

    @State private var spin = false

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
                .trim(from: 0, to: min(1, Double(limit.percent) / 100))
                .stroke(Color.forLimit(index),
                        style: StrokeStyle(lineWidth: metrics.ring, lineCap: .round))
                // Trims start at three o'clock; usage reads better from the top.
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: limit.percent)
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
            .onAppear { animate() }
            .onChange(of: mood) { _, _ in animate() }
    }

    /// A thin arc tracking inside the gauge while a session is mid-turn — the
    /// one moving part, and only when something is actually happening.
    @ViewBuilder
    private var tracker: some View {
        if mood == .working {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Color.workingGreen,
                        style: StrokeStyle(lineWidth: metrics.spinner, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .padding(metrics.spinnerInset)
        }
    }

    private func animate() {
        spin = false
        guard mood == .working else { return }
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { spin = true }
    }
}
