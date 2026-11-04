#!/usr/bin/env swift
// Rebuilds every app icon size from Resources/CherryToolsIcon.png on the macOS icon grid.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
guard let art = NSImage(contentsOf: resources.appendingPathComponent("CherryToolsIcon.png")) else {
    fatalError("Run from the repository root.")
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let unit = CGFloat(size) / 1024
    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.98, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.97, green: 0.89, blue: 0.84, alpha: 1))!.draw(in: shape, angle: -90)
    art.draw(in: body.insetBy(dx: 96 * unit, dy: 96 * unit))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = resources.appendingPathComponent("CherryTools.iconset")
let catalog = resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        let data = render(size: point * scale)
        try data.write(to: iconset.appendingPathComponent(name))
        try data.write(to: catalog.appendingPathComponent(name))
    }
}
