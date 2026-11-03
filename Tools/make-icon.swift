// Renders Freshly's app icon: a minty gradient squircle with a glassy refresh glyph.
// Usage: swift Tools/make-icon.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let squircle = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.82, blue: 0.68, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.95, alpha: 1),
    ])!
    gradient.draw(in: squircle, angle: -60)

    // Soft top highlight for a glassy sheen.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let sheen = NSGradient(colors: [.white.withAlphaComponent(0.35), .white.withAlphaComponent(0)])!
    sheen.draw(in: NSRect(x: inset.minX, y: inset.midY, width: inset.width, height: inset.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height))
    }
    if let spark = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 150, weight: .bold).applying(.init(paletteColors: [.white]))) {
        let s = spark.size
        spark.draw(in: NSRect(x: inset.maxX - s.width - 70, y: inset.maxY - s.height - 70, width: s.width, height: s.height))
    }
    return true
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("icon_\(px).png"))
}
print("Wrote icons to \(outDir.path)")
