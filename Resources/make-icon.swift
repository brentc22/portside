// Renders Resources/Portside.icns. Run: swift Resources/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "Resources/Portside.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

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
    NSGradient(colors: [NSColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 1),
                        NSColor(red: 0.10, green: 0.24, blue: 0.30, alpha: 1)])!
        .draw(in: path, angle: 90)

    // Three "server" rows, each with a status light.
    let rowW = body.width * 0.62, rowH = body.height * 0.14, gap = body.height * 0.06
    let x = body.midX - rowW / 2
    let lights: [NSColor] = [.systemGreen, .systemGreen, NSColor.white.withAlphaComponent(0.25)]
    for i in 0..<3 {
        let y = body.midY + rowH / 2 + gap - CGFloat(i) * (rowH + gap) - rowH / 2
        let row = NSRect(x: x, y: y, width: rowW, height: rowH)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: row, xRadius: rowH * 0.3, yRadius: rowH * 0.3).fill()
        let d = rowH * 0.36
        lights[i].setFill()
        NSBezierPath(ovalIn: NSRect(x: row.minX + rowH * 0.38, y: row.midY - d / 2, width: d, height: d)).fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        let bar = NSRect(x: row.minX + rowH * 1.1, y: row.midY - rowH * 0.08, width: rowW * 0.45, height: rowH * 0.16)
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let data = render(px)
    if px <= 512 { try data.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try data.write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
}
