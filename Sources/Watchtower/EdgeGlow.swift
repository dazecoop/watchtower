import AppKit
import QuartzCore

/// A thin band of colour at the true edge of every screen, fading smoothly to
/// nothing a short way in, that glows while any session is mid-turn — the
/// ambient, glanceable version of the tile's own working indicator, visible
/// from across the room rather than only when you're looking at the window.
///
/// Built as a standalone prototype first and tuned interactively before this
/// file existed; the parameters below (`depth`, the power curve, the 30%
/// overall dimming) are the values that came out of that process, not a
/// first guess.
///
/// Off by default, like every other optional Watchtower feature — see
/// `FleetStore.edgeGlow`.
final class EdgeGlowPanel: NSPanel {
    /// How far in from the true edge the glow reaches before it is gone.
    /// Deliberately small: a thin, edge-hugging glow reads as ambient light
    /// off the bezel; anything deep intrudes into the screen like a filter.
    private let depth: CGFloat = 50

    /// The falloff's shape: `pow(1 - t, power)` stays close to full strength
    /// near the edge, then drops away faster as it approaches `depth` —
    /// landed on after `linear` and a hold-then-ease curve both still read
    /// as having a visible edge where they reached zero.
    private let power: CGFloat = 3

    /// Flat multiplier over the whole thing, pulse included — "turn it down
    /// by 30%" from where the curve alone put it.
    private let opacity: CGFloat = 0.7

    private let pulseMin: CGFloat = 0.55
    private let pulseDuration: TimeInterval = 1.7
    private let sweepDuration: TimeInterval = 5

    /// A built-in notched display only rounds its top corners, to match the
    /// camera housing; the bottom corners are the regular square panel edge.
    private let topRadius: CGFloat
    private let bottomRadius: CGFloat

    static let fadeIn: TimeInterval = 0.55
    static let fadeOut: TimeInterval = 0.65

    /// How far past ordinary white this screen can currently push a colour —
    /// 1.0 means no headroom at all. Core Animation renders Extended Dynamic
    /// Range automatically for a CGColor built in an extended colour space
    /// with component values above 1.0, and tone-maps it straight back down
    /// to an ordinary colour on a screen that can't do better, so there is no
    /// separate SDR code path to maintain — the same colour value just looks
    /// like a plain colour there. `maximumExtendedDynamicRangeColorComponentValue`
    /// is the amount actually usable right now, which moves with the
    /// screen's brightness; `maximumPotentialExtendedDynamicRangeColorComponentValue`
    /// is the hardware ceiling and can overstate what's currently available.
    private let edrHeadroom: CGFloat

    init(screen: NSScreen) {
        (topRadius, bottomRadius) = Self.cornerRadii(for: screen)
        edrHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue

        // `.nonactivatingPanel` matters even with `ignoresMouseEvents`:
        // without it a borderless panel can still be asked to activate or
        // become key in edge cases, which is exactly the kind of thing that
        // can leave input routed somewhere other than the app underneath —
        // a click-through overlay has to get this right every time.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        // `.screenSaver` was tried first and behaved like one in more ways
        // than intended: Spaces didn't carry it along, and it didn't play as
        // well with input routing to the app underneath either. `.statusBar`
        // is the level the notch panel itself used to use, proven to both
        // follow every Space and leave everything beneath it fully
        // interactive.
        //
        // The notch now sits one level *above* this (see `Overlay.swift`)
        // rather than this sitting one below it: `.statusBar - 1` is exactly
        // `.mainMenu` — the system menu bar's own level — and landing there
        // meant the menu bar won the tie along the very top edge, wiping out
        // the one strip of glow that mattered most. Raising the notch
        // instead costs nothing, since nothing else is meant to sit between
        // the two.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        contentView = host
        build(on: host.layer!, size: screen.frame.size, scale: screen.backingScaleFactor)

        // Invisible until `fadeIn()` runs — set before the window is ever
        // ordered front, so there's no one-frame flash at full strength.
        alphaValue = 0
    }

    /// `(top, bottom)` corner radius in points. The real bezel radius isn't
    /// public API; `_cornerRadius` is the private property a few existing
    /// notch-overlay apps read, guarded behind `responds(to:)` so an
    /// unavailable or renamed key degrades to a plain guess rather than
    /// crashing. `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (macOS 12+,
    /// public) are non-nil exactly on displays with a camera housing, which
    /// is the reliable signal for "top corners are rounded, bottom are not"
    /// even when the private property isn't there to ask.
    private static func cornerRadii(for screen: NSScreen) -> (top: CGFloat, bottom: CGFloat) {
        let hasNotch = screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
        let selector = NSSelectorFromString("_cornerRadius")
        if screen.responds(to: selector),
           let value = screen.value(forKey: "_cornerRadius") as? CGFloat, value > 0 {
            return (value, hasNotch ? 0 : value)
        }
        return hasNotch ? (24, 0) : (0, 0)
    }

    /// A rectangle with its four corners rounded independently — `CGPath`'s
    /// own `roundedRect` initialiser only takes one radius for all four,
    /// which can't express a notched display's shape.
    private func roundedRect(_ rect: CGRect, topLeft: CGFloat, topRight: CGFloat,
                             bottomRight: CGFloat, bottomLeft: CGFloat) -> CGPath {
        let tl = min(topLeft, rect.width / 2, rect.height / 2)
        let tr = min(topRight, rect.width / 2, rect.height / 2)
        let br = min(bottomRight, rect.width / 2, rect.height / 2)
        let bl = min(bottomLeft, rect.width / 2, rect.height / 2)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + bl))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + bl, y: rect.minY), radius: bl)
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + br), radius: br)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - tr, y: rect.maxY), radius: tr)
        path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - tl), radius: tl)
        path.closeSubpath()
        return path
    }

    /// Draws the falloff shape once, as an image: many rounded-rect outlines,
    /// each inset a little further and a little more transparent, following
    /// the window's own (asymmetric) corners so the fade wraps them smoothly
    /// instead of breaking at the curve. Stacking many thin, barely-
    /// overlapping strokes like this is the standard way to get a soft
    /// distance-based gradient out of Core Graphics, which has no "fade with
    /// distance from this shape" primitive of its own.
    ///
    /// Used only as a CALayer mask, so only its alpha channel matters — the
    /// stroke colour drawn is white regardless of what the glow itself ends
    /// up coloured.
    private func maskImage(size: CGSize, scale: CGFloat) -> CGImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let ctx = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)

        let bounds = CGRect(origin: .zero, size: size)
        let steps = max(80, Int(depth))
        let lineWidth = depth / CGFloat(steps) + 1.5   // slight overlap, no seams
        ctx.setLineWidth(lineWidth)

        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps - 1)
            let inset = t * depth
            let rect = bounds.insetBy(dx: inset, dy: inset)
            guard rect.width > 0, rect.height > 0 else { break }

            let alpha = pow(max(0, 1 - t), power)
            let path = roundedRect(rect,
                                   topLeft: max(0, topRadius - inset), topRight: max(0, topRadius - inset),
                                   bottomRight: max(0, bottomRadius - inset), bottomLeft: max(0, bottomRadius - inset))
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            ctx.addPath(path)
            ctx.strokePath()
        }
        return ctx.makeImage()!
    }

    /// A colour in the `extendedSRGB` space, its components scaled by
    /// `boost` — pass `boost > 1` on a screen with EDR headroom to get an
    /// actual overbright highlight rather than one merely clamped to white.
    /// Falls back to the ordinary (unextended) colour if the extended colour
    /// space is ever unavailable, which keeps this safe to call unconditionally.
    private func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, boost: CGFloat) -> CGColor {
        guard boost > 1, let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let color = CGColor(colorSpace: space, components: [r * boost, g * boost, b * boost, 1])
        else {
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        }
        return color
    }

    private func build(on root: CALayer, size: CGSize, scale: CGFloat) {
        let bounds = CGRect(origin: .zero, size: size)

        // The sweep's peak gets the EDR push, not its base colour: a true
        // flash of overbright light riding through an otherwise ordinary
        // gradient reads as the glow catching the light, not as a screen
        // that's simply been turned up. Capped well under the full headroom
        // so it stays a highlight rather than blowing out into white.
        let peakBoost = min(edrHeadroom, 1.6)
        let deep = color(0.06, 0.55, 0.42, boost: 1)
        let bright = color(0.36, 0.95, 0.62, boost: peakBoost)
        let lime = color(0.62, 0.98, 0.55, boost: peakBoost)

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = maskImage(size: size, scale: scale)
        mask.contentsScale = scale

        // The colour, swept slowly across the screen on a diagonal.
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.type = .axial
        gradient.colors = [deep, bright, lime, bright, deep]
        gradient.locations = [0, 0.25, 0.5, 0.75, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.mask = mask

        let sweepStart = CABasicAnimation(keyPath: "startPoint")
        sweepStart.fromValue = CGPoint(x: 0, y: 0)
        sweepStart.toValue = CGPoint(x: 1, y: 0)
        sweepStart.duration = sweepDuration
        sweepStart.autoreverses = true
        sweepStart.repeatCount = .greatestFiniteMagnitude
        sweepStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(sweepStart, forKey: "sweepStart")

        let sweepEnd = CABasicAnimation(keyPath: "endPoint")
        sweepEnd.fromValue = CGPoint(x: 1, y: 1)
        sweepEnd.toValue = CGPoint(x: 0, y: 1)
        sweepEnd.duration = sweepDuration
        sweepEnd.autoreverses = true
        sweepEnd.repeatCount = .greatestFiniteMagnitude
        sweepEnd.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(sweepEnd, forKey: "sweepEnd")

        // The flat "turn it down 30%" multiplier, separate from the animated
        // breathing pulse on the gradient itself, so the two combine (Core
        // Animation multiplies a child's opacity by its parent's) rather
        // than one overriding the other.
        let container = CALayer()
        container.opacity = Float(opacity)
        container.addSublayer(gradient)
        root.addSublayer(container)

        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = pulseMin
        breathe.toValue = 1.0
        breathe.duration = pulseDuration
        breathe.autoreverses = true
        breathe.repeatCount = .greatestFiniteMagnitude
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(breathe, forKey: "breathe")
    }

    /// Brings the panel on screen already invisible, then eases its own
    /// opacity up — so the glow arrives rather than appearing mid-frame.
    func fadeIn() {
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// The reverse: eases out, then actually removes the panel — the two
    /// have to happen in that order, or the glow would just vanish and the
    /// fade would animate nothing.
    func fadeOut(then done: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            done()
        })
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one `EdgeGlowPanel` per screen and fades the set in or out together.
/// `apply(_:)` is idempotent, the same shape as `SleepGuard.apply` — callers
/// hand it the current answer on every refresh without tracking transitions
/// themselves.
@MainActor
final class EdgeGlowController {
    private(set) var showing = false
    private var panels: [EdgeGlowPanel] = []
    private var screenWatch: Any?

    func apply(_ wanted: Bool) {
        guard wanted != showing else { return }
        showing = wanted
        wanted ? show() : hide()
    }

    private func show() {
        guard panels.isEmpty else { return }
        panels = NSScreen.screens.map { EdgeGlowPanel(screen: $0) }
        panels.forEach { $0.fadeIn() }

        // A display connected or disconnected while the glow is up: rebuild
        // to match, rather than leaving a stale panel sized for a screen
        // that's gone, or a new screen with no glow on it at all.
        screenWatch = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForScreenChange() }
        }
    }

    private func rebuildForScreenChange() {
        guard showing else { return }
        let stale = panels
        panels = NSScreen.screens.map { EdgeGlowPanel(screen: $0) }
        panels.forEach { $0.fadeIn() }
        stale.forEach { $0.fadeOut {} }
    }

    private func hide() {
        if let screenWatch { NotificationCenter.default.removeObserver(screenWatch) }
        screenWatch = nil

        let outgoing = panels
        panels = []
        outgoing.forEach { panel in
            panel.fadeOut {}
        }
    }
}
