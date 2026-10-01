import SwiftUI
import AppKit
import QuartzCore

// The three idle animations — the breathing asterisk, the pulse ring and the
// shimmer sweep — are Core Animation layers rather than SwiftUI animations.
//
// This is not a micro-optimisation. A SwiftUI animation, however small and
// however well isolated in its own leaf view, keeps `NSHostingView` needing
// layout, and AppKit then runs a full view-graph render for the whole window
// on every display cycle. On a 120 Hz display that was measured at ~14% of a
// core for six tiles with two sessions working, and it grows with the number
// of tiles — nothing to do with what is actually animating. Moving the same
// animations onto layers hands them to the render server: the main thread sets
// them up once and does no work per frame.
//
// Each one is still wrapped in a plain SwiftUI view, so the call sites read the
// same and the `liveTicking` guards still tear them down off-screen.

/// Base for a view whose whole job is to run one layer animation.
private class AnimatedLayerView: NSView {
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Breathing asterisk

/// The marker that breathes while a session is mid-turn.
struct BreathingMark: NSViewRepresentable {
    static let pointSize: CGFloat = 9

    /// An `NSViewRepresentable` has no size of its own in a SwiftUI stack, so
    /// the glyph is measured once here and the call site is given that frame.
    /// Without it the mark stretches and pushes the gerund to the far edge.
    static let size: CGSize = {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
        return NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?.size ?? CGSize(width: 10, height: 10)
    }()

    func makeNSView(context: Context) -> NSView { MarkView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class MarkView: AnimatedLayerView {
        private let glyph = CALayer()

        override init() {
            super.init()
            let config = NSImage.SymbolConfiguration(pointSize: BreathingMark.pointSize,
                                                     weight: .black)
            let image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)

            glyph.contentsGravity = .center
            if let image {
                glyph.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                glyph.frame = CGRect(origin: .zero, size: image.size)
                // Tint the template glyph by using it as a mask over the colour.
                let mask = CALayer()
                mask.contents = glyph.contents
                mask.frame = glyph.bounds
                glyph.contents = nil
                glyph.backgroundColor = NSColor(Color.workingGreen).cgColor
                glyph.mask = mask
            }
            layer?.addSublayer(glyph)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.35
            fade.toValue = 1.0
            fade.duration = 0.75
            fade.autoreverses = true
            fade.repeatCount = .greatestFiniteMagnitude
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.isRemovedOnCompletion = false
            glyph.add(fade, forKey: "breathe")
        }

        override var intrinsicContentSize: NSSize { glyph.bounds.size }

        override func layout() {
            super.layout()
            glyph.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }
}

// MARK: - Pulse ring

/// The ring that swells out of a working session's status dot.
struct PulseRing: NSViewRepresentable {
    static let diameter: CGFloat = 22

    func makeNSView(context: Context) -> NSView { RingView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class RingView: AnimatedLayerView {
        private let ring = CALayer()

        override init() {
            super.init()
            let d = PulseRing.diameter
            ring.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            ring.cornerRadius = d / 2
            ring.backgroundColor = NSColor(Color.workingGreen.opacity(0.30)).cgColor
            ring.opacity = 0
            layer?.addSublayer(ring)

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.45
            grow.toValue = 1.0

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 1.6
            group.repeatCount = .greatestFiniteMagnitude
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = false
            ring.add(group, forKey: "pulse")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: PulseRing.diameter, height: PulseRing.diameter)
        }

        override func layout() {
            super.layout()
            ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }
}

// MARK: - Shimmer sweep

/// The highlight that travels across a block while its turn is still running.
struct ShimmerSweep: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SweepView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class SweepView: AnimatedLayerView {
        private let band = CAGradientLayer()
        private var animatedWidth: CGFloat = 0

        override init() {
            super.init()
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            band.locations = [0, 0.45, 0.50, 0.55, 1] as [NSNumber]
            layer?.addSublayer(band)
            applyColours()
        }

        /// `Color.primary` resolves against the current appearance, so the
        /// highlight has to be re-resolved when the theme flips.
        private func applyColours() {
            let base = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
            let alphas: [CGFloat] = [0, 0.07, 0.13, 0.07, 0]
            band.colors = alphas.map { base.withAlphaComponent($0).cgColor }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance { applyColours() }
        }

        override func layout() {
            super.layout()
            band.frame = bounds
            guard bounds.width > 0, bounds.width != animatedWidth else { return }
            animatedWidth = bounds.width

            // Matches the old SwiftUI sweep: one band width travelling from
            // 1.8 widths off the left to 1.8 off the right, on a loop.
            let travel = bounds.width * 1.8
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = -travel
            slide.toValue = travel
            slide.duration = 2.4
            slide.repeatCount = .greatestFiniteMagnitude
            slide.timingFunction = CAMediaTimingFunction(name: .linear)
            slide.isRemovedOnCompletion = false
            band.add(slide, forKey: "sweep")
        }
    }
}

// MARK: - Notch spinner

/// The arc that tracks around the notch's gauge while a session is mid-turn.
///
/// It was a `@State` rotation read in `UsageGauge.body`, so every frame
/// re-evaluated the gauge — all of its rings, the mark and the layout around
/// them. With the notch left on, that was the largest thing the app did once
/// the window's own animations were fixed.
struct SpinnerArc: NSViewRepresentable {
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> NSView { ArcView(lineWidth: lineWidth) }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ArcView)?.lineWidth = lineWidth
    }

    private final class ArcView: AnimatedLayerView {
        private let arc = CAShapeLayer()
        private var laidOut: CGRect = .zero

        var lineWidth: CGFloat {
            didSet {
                guard lineWidth != oldValue else { return }
                laidOut = .zero
                needsLayout = true
            }
        }

        init(lineWidth: CGFloat) {
            self.lineWidth = lineWidth
            super.init()
            arc.fillColor = nil
            arc.strokeColor = NSColor(Color.workingGreen).cgColor
            arc.lineCap = .round
            layer?.addSublayer(arc)

            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = -2 * Double.pi          // clockwise on screen
            turn.duration = 2.6
            turn.repeatCount = .greatestFiniteMagnitude
            turn.timingFunction = CAMediaTimingFunction(name: .linear)
            turn.isRemovedOnCompletion = false
            arc.add(turn, forKey: "spin")
        }

        override func layout() {
            super.layout()
            guard bounds != laidOut, bounds.width > 0 else { return }
            laidOut = bounds

            arc.lineWidth = lineWidth
            arc.bounds = CGRect(origin: .zero, size: bounds.size)
            arc.position = CGPoint(x: bounds.midX, y: bounds.midY)

            // A 0.22 turn of the circle, matching the old SwiftUI trim.
            let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
            let centre = CGPoint(x: bounds.midX - bounds.minX, y: bounds.midY - bounds.minY)
            let path = CGMutablePath()
            path.addArc(center: centre, radius: radius,
                        startAngle: 0, endAngle: 0.22 * 2 * .pi, clockwise: false)
            arc.path = path
        }
    }
}
