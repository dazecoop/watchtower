// Generates docs/social-preview.png — the 1280x640 card GitHub serves as
// og:image once uploaded under Settings → General → Social preview.
// Exact pixel dimensions matter, so this draws into a bitmap rep rather than
// using lockFocus, which silently doubles on a Retina display.
//
// Usage: swiftc -O Resources/MakeSocial.swift -o /tmp/makesocial
//        /tmp/makesocial [shots-dir]
//
// Takes its artwork from Resources/Capture.sh rather than from
// docs/screenshot.png: that file is now a light-backed composite, which would
// sit badly on this card's dark gradient.
import AppKit

let shots = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/watchtower-shots"

let W = 1280.0, H = 640.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

let space = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.039, green: 0.043, blue: 0.063, alpha: 1),
    CGColor(red: 0.075, green: 0.082, blue: 0.118, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// App mark: three stacked tiles, the top one lit green.
let tileW = 74.0, tileH = 19.0, step = 28.0, markTop = 540.0
let marks: [(CGColor, CGFloat)] = [
    (CGColor(red: 0.26, green: 0.80, blue: 0.47, alpha: 1), 0.62),
    (CGColor(red: 0.98, green: 0.70, blue: 0.22, alpha: 1), 0.46),
    (CGColor(red: 0.62, green: 0.66, blue: 0.76, alpha: 1), 0.34)
]
for (i, m) in marks.enumerated() {
    let tile = CGRect(x: 64, y: markTop - Double(i) * step, width: tileW, height: tileH)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(m.0)
    ctx.fillEllipse(in: CGRect(x: tile.minX + 8, y: tile.midY - 3.5, width: 7, height: 7))
    let bar = CGRect(x: tile.minX + 22, y: tile.midY - 2, width: tileW * m.1, height: 4)
    ctx.setFillColor(m.0.copy(alpha: 0.55)!)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 2, cornerHeight: 2, transform: nil))
    ctx.fillPath()
}

func attrs(_ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat,
           _ tracking: CGFloat, _ leading: CGFloat = 0) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = leading
    return [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
        .kern: tracking,
        .paragraphStyle: style
    ]
}

/// draw(at:) takes a bottom-left origin, which keeps the layout predictable.
func line(_ s: String, x: CGFloat, baseline: CGFloat, _ a: [NSAttributedString.Key: Any]) {
    NSAttributedString(string: s, attributes: a).draw(at: NSPoint(x: x, y: baseline))
}

line("Watchtower", x: 62, baseline: 396, attrs(62, .bold, 1, -1.2))
NSAttributedString(string: "See every Claude Code session\nat a glance",
                   attributes: attrs(25, .medium, 0.72, 0, 7))
    .draw(with: CGRect(x: 64, y: 100, width: 452, height: 250), options: [.usesLineFragmentOrigin])
line("macOS  ·  open source  ·  read-only", x: 64, baseline: 54, attrs(16, .medium, 0.38, 0.6))

// A monitor, so the notch has an edge to sit on. The branding stays outside
// it, on the card itself.
func shot(_ name: String) -> (image: NSImage, pixels: CGSize)? {
    guard let image = NSImage(contentsOfFile: "\(shots)/\(name).png"),
          let rep = image.representations.first else { return nil }
    return (image, CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
}

// Bleeds off the right so the dashboard keeps its detail; the left edge and
// the corners above and below it stay in frame.
let screen = CGRect(x: 560, y: 46, width: 780, height: H - 92)
let screenPath = CGPath(roundedRect: screen, cornerWidth: 26, cornerHeight: 26, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -14, height: -16), blur: 44,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.62))
ctx.addPath(screenPath)
ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()

// Wallpaper: a cool-to-warm sweep with soft blooms, enough to read as a
// desktop without competing with the UI on top of it.
let paper = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.047, green: 0.090, blue: 0.180, alpha: 1),
    CGColor(red: 0.063, green: 0.231, blue: 0.325, alpha: 1),
    CGColor(red: 0.137, green: 0.353, blue: 0.376, alpha: 1),
    CGColor(red: 0.361, green: 0.247, blue: 0.231, alpha: 1)
] as CFArray, locations: [0, 0.38, 0.66, 1])!
ctx.drawLinearGradient(paper, start: CGPoint(x: screen.minX, y: screen.maxY),
                       end: CGPoint(x: screen.maxX, y: screen.minY), options: [])

func bloom(_ at: CGPoint, radius: CGFloat, color: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: at, startRadius: 0,
                           endCenter: at, endRadius: radius, options: [])
}
bloom(CGPoint(x: screen.minX + 110, y: screen.maxY - 60), radius: 330,
      color: CGColor(red: 0.27, green: 0.78, blue: 0.88, alpha: 0.50))
bloom(CGPoint(x: screen.minX + 430, y: screen.minY + 130), radius: 380,
      color: CGColor(red: 0.98, green: 0.55, blue: 0.26, alpha: 0.32))

// The dashboard, sitting on the desktop and running off the right edge.
if let (image, size) = shot("nocturne") {
    let drawH = 452.0
    let frame = CGRect(x: screen.minX + 126, y: screen.midY - drawH / 2 - 6,
                       width: drawH * size.width / size.height, height: drawH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -8, height: -14), blur: 34,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.58))
    image.draw(in: frame)
    ctx.restoreGState()
}
ctx.restoreGState()

// A lit edge keeps the panel from melting into the card behind it.
ctx.addPath(screenPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.17))
ctx.setLineWidth(1.5)
ctx.strokePath()

// The notch, flush to the screen's left edge exactly as it sits in use.
// Captured at twice size.
if let (image, size) = shot("notch") {
    let w = size.width / 2 * 0.92
    let h = size.height / 2 * 0.92
    image.draw(in: CGRect(x: screen.minX, y: screen.midY - h / 2, width: w, height: h))
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/social-preview.png"))
