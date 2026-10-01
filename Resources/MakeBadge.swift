// Generates docs/download-macos.png — a dark pill in the familiar store-badge
// shape, but with its own download glyph and wording. Deliberately carries no
// Apple logo or store name: this app is not distributed through the App Store.
import AppKit

let scale = 2.0
let w = 236.0 * scale, h = 62.0 * scale
let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Pill
let rect = CGRect(x: scale, y: scale, width: w - scale * 2, height: h - scale * 2)
let pill = CGPath(roundedRect: rect, cornerWidth: 11 * scale, cornerHeight: 11 * scale, transform: nil)
ctx.addPath(pill)
ctx.setFillColor(CGColor(red: 0.043, green: 0.043, blue: 0.055, alpha: 1))
ctx.fillPath()
ctx.addPath(pill)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.setLineWidth(1.0 * scale)
ctx.strokePath()

// Download glyph: arrow into a tray
let gx = 30.0 * scale, gy = h / 2
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(2.1 * scale)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

ctx.move(to: CGPoint(x: gx, y: gy + 13 * scale))
ctx.addLine(to: CGPoint(x: gx, y: gy - 4.5 * scale))
ctx.strokePath()

ctx.move(to: CGPoint(x: gx - 6.5 * scale, y: gy + 2 * scale))
ctx.addLine(to: CGPoint(x: gx, y: gy - 4.8 * scale))
ctx.addLine(to: CGPoint(x: gx + 6.5 * scale, y: gy + 2 * scale))
ctx.strokePath()

ctx.move(to: CGPoint(x: gx - 10.5 * scale, y: gy - 9 * scale))
ctx.addLine(to: CGPoint(x: gx - 10.5 * scale, y: gy - 13 * scale))
ctx.addLine(to: CGPoint(x: gx + 10.5 * scale, y: gy - 13 * scale))
ctx.addLine(to: CGPoint(x: gx + 10.5 * scale, y: gy - 9 * scale))
ctx.strokePath()

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, tracking: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * scale, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
        .kern: tracking * scale
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: x, y: y))
}

draw("DOWNLOAD FOR", x: 52 * scale, y: 33 * scale, size: 9, weight: .medium, alpha: 0.62, tracking: 1.5)
draw("macOS", x: 51 * scale, y: 12 * scale, size: 20, weight: .semibold, alpha: 1.0, tracking: -0.2)

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
