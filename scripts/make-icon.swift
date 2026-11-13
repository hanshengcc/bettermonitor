// Generates Resources/AppIcon.icon (Icon Composer format) for BetterMonitor:
// blue gradient plate, white display, warm sparkle = "make the screen crisp".
// Usage: swift scripts/make-icon.swift   (run from the project root)
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Four-point star with concave sides.
func sparkle(center: NSPoint, radius: CGFloat, pinch: CGFloat = 0.18) -> NSBezierPath {
    let path = NSBezierPath()
    let tips = [NSPoint(x: 0, y: 1), NSPoint(x: 1, y: 0), NSPoint(x: 0, y: -1), NSPoint(x: -1, y: 0)]
        .map { NSPoint(x: center.x + $0.x * radius, y: center.y + $0.y * radius) }
    let inner = radius * pinch
    path.move(to: tips[0])
    for index in 0..<4 {
        let next = tips[(index + 1) % 4]
        let control = NSPoint(
            x: center.x + ((tips[index].x - center.x) + (next.x - center.x)) / radius * inner,
            y: center.y + ((tips[index].y - center.y) + (next.y - center.y)) / radius * inner
        )
        path.curve(to: next, controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}

func drawDisplay() {
    let ink = NSColor.white
    let screen = rounded(NSRect(x: 196, y: 372, width: 632, height: 432), 78)
    screen.lineWidth = 58
    ink.setStroke()
    screen.stroke()
    ink.setFill()
    rounded(NSRect(x: 470, y: 262, width: 84, height: 96), 10).fill()   // neck
    rounded(NSRect(x: 346, y: 214, width: 332, height: 58), 29).fill()  // foot
}

func drawSparkles() {
    color(0xFFD45C).setFill()
    sparkle(center: NSPoint(x: 512, y: 588), radius: 128).fill()
    color(0xFFE9A8).setFill()
    sparkle(center: NSPoint(x: 666, y: 690), radius: 46).fill()
}

func layer(_ draw: () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    draw()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    let pixels = Int(canvas)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let bundle = URL(fileURLWithPath: "Resources/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try writePNG(layer(drawDisplay), to: assets.appendingPathComponent("display.png"))
try writePNG(layer(drawSparkles), to: assets.appendingPathComponent("sparkle.png"))

let json = """
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.36078,0.55686,1.00000,1.00000",
      "srgb:0.16471,0.23922,0.78431,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [ { "image-name" : "sparkle.png", "name" : "sparkle" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.4 },
      "translucency" : { "enabled" : false, "value" : 0.4 }
    },
    {
      "layers" : [ { "image-name" : "display.png", "name" : "display" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.25 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
"""
try json.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("wrote \(bundle.path)")
