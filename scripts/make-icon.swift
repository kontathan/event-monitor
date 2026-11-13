#!/usr/bin/env swift
// Zeichnet das App-Logo per Code und erzeugt Resources/AppIcon.icns.
// Aufruf: swift scripts/make-icon.swift
//
// Motiv: ein Kalenderblatt mit Standort-Pin auf einem Verlauf von Mainz-Rot zu Wiesbaden-Blau.

import AppKit

let canvas: CGFloat = 1024

func draw(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // 1. Hintergrund (macOS-Raster: 824 × 824 mit Rand für den Schatten)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.30))
    ctx.addPath(rounded(tile, 185))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rounded(tile, 185))
    ctx.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [color(0xE0263F), color(0x8A2F8F), color(0x1E5FC8)] as CFArray,
                                locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: tile.minX, y: tile.maxY),
                           end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // dezenter Glanz oben
    let gloss = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])
    ctx.restoreGState()

    // 2. Kalenderblatt
    let card = CGRect(x: 232, y: 232, width: 560, height: 520)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.28))
    ctx.addPath(rounded(card, 70))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Kopfleiste
    ctx.saveGState()
    ctx.addPath(rounded(card, 70))
    ctx.clip()
    ctx.setFillColor(color(0x23233A))
    ctx.fill(CGRect(x: card.minX, y: card.maxY - 130, width: card.width, height: 130))
    ctx.restoreGState()

    // Ringe
    for x in [card.minX + 150, card.maxX - 150] {
        ctx.addPath(rounded(CGRect(x: x - 22, y: card.maxY - 70, width: 44, height: 120), 22))
        ctx.setFillColor(color(0xF2F2F7))
        ctx.fillPath()
    }

    // Raster aus Tagen (Punkte), einer davon wird vom Pin markiert
    let dotColor = color(0xD5D5E0)
    for row in 0..<3 {
        for col in 0..<5 {
            let cx = card.minX + 90 + CGFloat(col) * 95
            let cy = card.minY + 95 + CGFloat(row) * 95
            ctx.addEllipse(in: CGRect(x: cx - 20, y: cy - 20, width: 40, height: 40))
        }
    }
    ctx.setFillColor(dotColor)
    ctx.fillPath()

    // 3. Standort-Pin
    let pinCenter = CGPoint(x: 512, y: 470)
    let r: CGFloat = 125
    let tip = CGPoint(x: pinCenter.x, y: pinCenter.y - r * 2.05)
    // Pin als eine Kontur: von der Spitze tangential an den Kreis, oben herum, zurück zur Spitze.
    let angle = asin(r / (pinCenter.y - tip.y)) // halber Öffnungswinkel an der Spitze
    let pinPath = CGMutablePath()
    pinPath.move(to: tip)
    pinPath.addArc(center: pinCenter, radius: r, startAngle: -angle, endAngle: .pi + angle, clockwise: false)
    pinPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.30))
    ctx.addPath(pinPath)
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pinPath)
    ctx.clip()
    let pinGradient = CGGradient(colorsSpace: space, colors: [color(0xFF5A4E), color(0xE0263F)] as CFArray,
                                 locations: [0, 1])!
    ctx.drawLinearGradient(pinGradient, start: CGPoint(x: 0, y: pinCenter.y + r), end: CGPoint(x: 0, y: tip.y), options: [])
    ctx.restoreGState()

    // Stern im Pin: „hier ist was los“
    let star = CGMutablePath()
    let outer: CGFloat = 70, inner: CGFloat = 30
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 + .pi / 2
        let radius = i.isMultiple(of: 2) ? outer : inner
        let p = CGPoint(x: pinCenter.x + radius * cos(a), y: pinCenter.y + radius * sin(a))
        i == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath()
    ctx.addPath(star)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(in: ctx)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appending(path: "Resources")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: resources.appending(path: "AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Fertig: Resources/AppIcon.icns und Resources/AppIcon.png" : "iconutil fehlgeschlagen")
