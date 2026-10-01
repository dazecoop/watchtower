// Generates AppIcon.png — a watchtower lens on a deep gradient.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded squircle backdrop with a diagonal gradient.
let inset = size * 0.085
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1),
    CGColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: inset, y: size - inset),
                       end: CGPoint(x: size - inset, y: inset), options: [])

// Three stacked tiles, the top one lit green: the fleet, at a glance.
let cx = size / 2
let tileW = size * 0.44
let tileH = size * 0.115
let gap = size * 0.055
let colors: [(CGColor, CGColor)] = [
    (CGColor(red: 0.26, green: 0.80, blue: 0.47, alpha: 1.0), CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)),
    (CGColor(red: 0.98, green: 0.70, blue: 0.22, alpha: 0.95), CGColor(red: 1, green: 1, blue: 1, alpha: 0.15)),
    (CGColor(red: 0.62, green: 0.66, blue: 0.76, alpha: 0.75), CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
]
for (i, pair) in colors.enumerated() {
    let y = cx + gap * 1.5 - Double(i) * (tileH + gap) - tileH / 2
    let tile = CGRect(x: cx - tileW / 2, y: y, width: tileW, height: tileH)
    ctx.setFillColor(pair.1)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tileH * 0.34, cornerHeight: tileH * 0.34, transform: nil))
    ctx.fillPath()

    // Status dot on the left edge of each tile.
    let dot = CGRect(x: tile.minX + tileH * 0.42, y: tile.midY - tileH * 0.17,
                     width: tileH * 0.34, height: tileH * 0.34)
    ctx.setFillColor(pair.0)
    ctx.fillEllipse(in: dot)

    // A short activity bar beside it.
    let bar = CGRect(x: dot.maxX + tileH * 0.30, y: tile.midY - tileH * 0.085,
                     width: tileW * (i == 0 ? 0.58 : (i == 1 ? 0.44 : 0.32)), height: tileH * 0.17)
    ctx.setFillColor(pair.0.copy(alpha: 0.65)!)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
    ctx.fillPath()
}
ctx.restoreGState()

// Hairline rim for definition on light backgrounds.
ctx.addPath(path)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.13))
ctx.setLineWidth(size * 0.006)
ctx.strokePath()

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
