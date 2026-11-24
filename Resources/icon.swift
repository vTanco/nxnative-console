// Draws the app icon: a red rounded square with a white game controller, as a 1024 PNG.
import AppKit
let S: CGFloat = 1024, B: CGFloat = 824
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let box = NSRect(x: (S - B) / 2, y: (S - B) / 2 - 10, width: B, height: B)
NSGradient(starting: NSColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1), ending: NSColor(red: 0.78, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185), angle: -90)
let cfg = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
if let sym = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
    let s = tinted.size; tinted.draw(in: NSRect(x: (S - s.width) / 2, y: (S - s.height) / 2 - 10, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
