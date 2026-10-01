// Generates docs/screenshot.png — the README hero.
//
// One scene rather than one window: a desktop with the themed dashboards
// stacked on it and the notch sitting on its edge, so the whole app is legible
// in a single image. Source art comes from Resources/Capture.sh.
//
// Usage: swiftc -O Resources/MakeShowcase.swift -o /tmp/makeshowcase
//        /tmp/makeshowcase [shots-dir]
//
// Drawn into a bitmap rep rather than with lockFocus, which silently doubles
// on a Retina display. Coordinates are logical points with the origin at the
// bottom left, and the context is scaled on the way out. 1.5x keeps the art
// comfortably sharper than GitHub renders it without the file getting heavy —
// 2x pushed it past 2 MB, mostly on the wallpaper gradient.
import AppKit

let shots = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/watchtower-shots"
let W = 1220.0, H = 800.0, scale = 1.5

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
ctx.scaleBy(x: scale, y: scale)

let space = CGColorSpaceCreateDeviceRGB()

func load(_ name: String) -> NSImage? {
    NSImage(contentsOfFile: "\(shots)/\(name).png")
}

/// Pixel size, not `NSImage.size` — screencapture files carry no DPI, so the
/// two agree today, but reading the rep keeps this honest at any scale.
func pixels(_ image: NSImage) -> CGSize {
    guard let rep = image.representations.first else { return image.size }
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

// MARK: - Page

ctx.setFillColor(CGColor(red: 0.953, green: 0.953, blue: 0.961, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// A dot grid, the way a product page frames a screenshot.
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.055))
let step = 22.0, dot = 2.4
for x in stride(from: 12.0, to: W, by: step) {
    for y in stride(from: 12.0, to: H, by: step) {
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
    }
}

// MARK: - Desktop

// Bleeds off the right and bottom, so only the edge the notch sits on and the
// corner above it are in frame.
let desk = CGRect(x: 64, y: -70, width: W, height: H - 58)
let deskPath = CGPath(roundedRect: desk, cornerWidth: 46, cornerHeight: 46, transform: nil)

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

// Wallpaper: a cool-to-warm sweep with a couple of soft blooms over it, which
// reads as a desktop without competing with the UI sitting on top.
let sweep = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.047, green: 0.090, blue: 0.180, alpha: 1),
    CGColor(red: 0.063, green: 0.231, blue: 0.325, alpha: 1),
    CGColor(red: 0.137, green: 0.353, blue: 0.376, alpha: 1),
    CGColor(red: 0.361, green: 0.247, blue: 0.231, alpha: 1)
] as CFArray, locations: [0, 0.38, 0.66, 1])!
ctx.drawLinearGradient(sweep, start: CGPoint(x: desk.minX, y: desk.maxY),
                       end: CGPoint(x: desk.maxX, y: desk.minY), options: [])

func bloom(_ at: CGPoint, radius: CGFloat, color: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [
        color, color.copy(alpha: 0)!
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: at, startRadius: 0,
                           endCenter: at, endRadius: radius, options: [])
}
bloom(CGPoint(x: desk.minX + 180, y: desk.maxY - 90), radius: 460,
      color: CGColor(red: 0.27, green: 0.78, blue: 0.88, alpha: 0.50))
bloom(CGPoint(x: desk.minX + 620, y: desk.minY + 220), radius: 560,
      color: CGColor(red: 0.98, green: 0.55, blue: 0.26, alpha: 0.34))
ctx.restoreGState()

// A hairline along the lit edge keeps the panel from melting into the page.
ctx.addPath(deskPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.setLineWidth(1)
ctx.strokePath()

// MARK: - Dashboards

/// Back to front, each stepped down and left so the stack reads as depth.
let stack: [(String, CGPoint)] = [
    ("light",    CGPoint(x: 386, y: 250)),
    ("slate",    CGPoint(x: 318, y: 168)),
    ("nocturne", CGPoint(x: 250, y: 86))
]
let shotWidth = 700.0

for (name, origin) in stack {
    guard let image = load(name) else { continue }
    let size = pixels(image)
    let frame = CGRect(x: origin.x, y: origin.y,
                       width: shotWidth, height: shotWidth * size.height / size.width)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -8, height: -16), blur: 40,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.52))
    image.draw(in: frame)
    ctx.restoreGState()
}

// MARK: - Notch

// Captured at twice its size, and drawn to match the dashboards' reduction so
// the scene stays to one scale. Flush to the desktop's edge, as in use.
if let notch = load("notch") {
    let size = pixels(notch)
    let reduction = shotWidth / 1160.0
    // Nudged up from a strict match: it is the smallest thing in the scene and
    // the one the picture is there to show.
    let emphasis = 1.95
    let w = size.width / 2 * reduction * emphasis
    let h = size.height / 2 * reduction * emphasis
    notch.draw(in: CGRect(x: desk.minX, y: 480, width: w, height: h))
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/screenshot.png"))
print("==> docs/screenshot.png")
