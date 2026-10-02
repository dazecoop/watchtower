// Generates docs/notch-summary.png and docs/notch-app.png — the open notch
// shown as it is in use: docked to the top of a screen, under the menu bar,
// with the desktop around it. The same page, desktop and wallpaper as
// MakeShowcase.swift, so the README's images read as one set.
//
// Usage: swiftc -O Resources/MakeNotchScenes.swift -o /tmp/makenotch
//        /tmp/makenotch [shots-dir]
//
// Reads notch-summary.png / notch-app.png (the open notch at 2x) from the
// shots dir, as written by Resources/CaptureStates.sh.
import AppKit

let shots = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/watchtower-shots"
let space = CGColorSpaceCreateDeviceRGB()

func load(_ name: String) -> NSImage? {
    NSImage(contentsOfFile: "\(shots)/\(name).png")
}

func pixels(_ image: NSImage) -> CGSize {
    guard let rep = image.representations.first else { return image.size }
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

/// One scene. `W` and `H` are the page size in points; the notch is drawn at
/// `notchScale` of its point size. Nothing else is on the desktop: the notch
/// is the subject, and a window behind it read as a second copy of the app.
func scene(_ name: String, W: Double, H: Double, notchScale: Double, out: String) {
    let scale = 1.5
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // MARK: Page

    ctx.setFillColor(CGColor(red: 0.953, green: 0.953, blue: 0.961, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.055))
    let step = 22.0, dot = 2.4
    for x in stride(from: 12.0, to: W, by: step) {
        for y in stride(from: 12.0, to: H, by: step) {
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
        }
    }

    // MARK: Desktop

    // The notch docks to the top edge, so that is the edge in frame: the
    // desktop bleeds off left, right and bottom, and its top corners show.
    let desk = CGRect(x: 48, y: -80, width: W - 96, height: H - 40 + 80)
    let deskPath = CGPath(roundedRect: desk, cornerWidth: 40, cornerHeight: 40, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 34,
                  color: CGColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 0.22))
    ctx.addPath(deskPath)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(deskPath)
    ctx.clip()

    let sweep = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.047, green: 0.090, blue: 0.180, alpha: 1),
        CGColor(red: 0.063, green: 0.231, blue: 0.325, alpha: 1),
        CGColor(red: 0.137, green: 0.353, blue: 0.376, alpha: 1),
        CGColor(red: 0.361, green: 0.247, blue: 0.231, alpha: 1)
    ] as CFArray, locations: [0, 0.38, 0.66, 1])!
    ctx.drawLinearGradient(sweep, start: CGPoint(x: desk.minX, y: desk.maxY),
                           end: CGPoint(x: desk.maxX, y: desk.minY), options: [])

    func bloom(_ at: CGPoint, radius: CGFloat, color: CGColor) {
        let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray,
                           locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: at, startRadius: 0, endCenter: at, endRadius: radius, options: [])
    }
    bloom(CGPoint(x: desk.minX + 180, y: desk.maxY - 90), radius: 460,
          color: CGColor(red: 0.27, green: 0.78, blue: 0.88, alpha: 0.50))
    bloom(CGPoint(x: desk.maxX - 260, y: desk.minY + 220), radius: 560,
          color: CGColor(red: 0.98, green: 0.55, blue: 0.26, alpha: 0.34))

    // The menu bar, which the notch sits under in use. A translucent band
    // with a few neutral marks where the menus and status items would be.
    let barHeight = 24.0
    let bar = CGRect(x: desk.minX, y: desk.maxY - barHeight, width: desk.width, height: barHeight)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.fill(bar)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.fillEllipse(in: CGRect(x: bar.minX + 18, y: bar.midY - 6, width: 12, height: 12))
    var x = bar.minX + 42.0
    for width in [44.0, 30.0, 30.0, 36.0, 30.0] {
        ctx.fill(CGRect(x: x, y: bar.midY - 3, width: width, height: 6).insetBy(dx: 0, dy: 0.5))
        x += width + 16
    }
    x = bar.maxX - 24
    for width in [12.0, 14.0, 12.0, 34.0] {
        x -= width
        ctx.fill(CGRect(x: x, y: bar.midY - 4, width: width, height: 8).insetBy(dx: 0, dy: 1))
        x -= 14
    }

    // MARK: Notch

    // Flush under the menu bar and centred along the edge, as in use.
    if let notch = load(name) {
        let size = pixels(notch)
        let w = size.width / 2 * notchScale
        let h = size.height / 2 * notchScale
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        notch.draw(in: CGRect(x: (W - w) / 2, y: desk.maxY - barHeight - h, width: w, height: h))
        ctx.restoreGState()
    }

    ctx.restoreGState()

    ctx.addPath(deskPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(1)
    ctx.strokePath()

    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("==> \(out)")
}

// The summary is small, so its scene is small too — just enough desktop
// around it to show where it sits. The full app is a panel the size of a
// window and gets the hero's page.
scene("notch-summary", W: 760, H: 400, notchScale: 1.0, out: "docs/notch-summary.png")
scene("notch-app", W: 1220, H: 800, notchScale: 0.86, out: "docs/notch-app.png")
