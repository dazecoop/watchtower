// Generates docs/social-preview.png — the 1280x640 card GitHub serves as
// og:image once uploaded under Settings → General → Social preview.
// Exact pixel dimensions matter, so this draws into a bitmap rep rather than
// using lockFocus, which silently doubles on a Retina display.
import AppKit

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
    .draw(with: CGRect(x: 64, y: 100, width: 500, height: 250), options: [.usesLineFragmentOrigin])
line("macOS  ·  open source  ·  read-only", x: 64, baseline: 54, attrs(16, .medium, 0.38, 0.6))

// Dashboard artwork, bleeding off the right edge so detail stays readable.
if let shot = NSImage(contentsOfFile: "docs/screenshot.png") {
    let drawH = 540.0, drawW = drawH * (shot.size.width / shot.size.height)
    let frame = CGRect(x: 566, y: (H - drawH) / 2, width: drawW, height: drawH)
    let clip = CGPath(roundedRect: frame, cornerWidth: 14, cornerHeight: 14, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -10, height: -14), blur: 38,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(clip)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    shot.draw(in: frame)
    ctx.restoreGState()

    ctx.addPath(clip)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.13))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/social-preview.png"))
