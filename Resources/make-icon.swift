// Renders Resources/Portside.icns and docs/icon.png. Run: swift Resources/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "Resources/Portside.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 body with a continuous-corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)

    // Drop shadow under the body, like the system icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    rgb(0x3B2BD0).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Harbour at dusk: coral sky into violet into deep blue water.
    NSGradient(colors: [rgb(0xFF8A3D), rgb(0xF2477E), rgb(0x8B3FE8), rgb(0x2F4BE0)],
               atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)!
        .draw(in: path, angle: -60)

    // Soft glow from the top so the body doesn't read flat.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: body.midX - body.width * 0.2, y: body.maxY),
              radius: 0, toCenter: NSPoint(x: body.midX - body.width * 0.2, y: body.maxY),
              radius: body.width * 0.8, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Three "server" rows as frosted glass cards, each with a status light.
    let rowW = body.width * 0.64, rowH = body.height * 0.15, gap = body.height * 0.055
    let x = body.midX - rowW / 2
    let lights = [rgb(0x3DF58A), rgb(0x3DF58A), rgb(0xFFD23F)]
    for i in 0..<3 {
        let y = body.midY + rowH / 2 + gap - CGFloat(i) * (rowH + gap) - rowH / 2
        let row = NSRect(x: x, y: y, width: rowW, height: rowH)
        let card = NSBezierPath(roundedRect: row, xRadius: rowH * 0.32, yRadius: rowH * 0.32)

        NSGraphicsContext.saveGraphicsState()
        let cardShadow = NSShadow()
        cardShadow.shadowColor = rgb(0x1A0B5C, 0.35)
        cardShadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        cardShadow.shadowBlurRadius = s * 0.025
        cardShadow.set()
        NSColor.white.withAlphaComponent(0.2).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0.04)])!
            .draw(in: card, angle: -90)
        NSColor.white.withAlphaComponent(0.45).setStroke()
        card.lineWidth = max(1, s * 0.004)
        card.stroke()

        // Light with a glow around it.
        let d = rowH * 0.38
        let dot = NSRect(x: row.minX + rowH * 0.38, y: row.midY - d / 2, width: d, height: d)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = lights[i]
        glow.shadowBlurRadius = d * 0.9
        glow.set()
        lights[i].setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setFill()
        let bar = NSRect(x: row.minX + rowH * 1.12, y: row.midY - rowH * 0.085, width: rowW * 0.44, height: rowH * 0.17)
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        NSColor.white.withAlphaComponent(0.4).setFill()
        let port = NSRect(x: bar.maxX + rowH * 0.3, y: bar.minY, width: rowW * 0.14, height: bar.height)
        NSBezierPath(roundedRect: port, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let data = render(px)
    if px <= 512 { try data.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try data.write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
    if px == 512 { try data.write(to: URL(fileURLWithPath: "docs/icon.png")) }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/Portside.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
print("written: Resources/Portside.icns, docs/icon.png")
