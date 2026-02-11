#!/usr/bin/env swift
// Generates WorklogApp icon — a rounded-rect clock face with a checkmark accent
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.04
    let cornerRadius = size * 0.22

    // Background gradient (deep indigo → blue)
    let bgPath = CGPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.18, green: 0.14, blue: 0.45, alpha: 1.0),
        CGColor(red: 0.22, green: 0.38, blue: 0.85, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: size),
                              end: CGPoint(x: size, y: 0),
                              options: [])
    }
    ctx.restoreGState()

    // Clock face (white circle)
    let center = CGPoint(x: size / 2, y: size / 2)
    let faceRadius = size * 0.32
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addArc(center: center, radius: faceRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // Hour markers (12 small dots)
    for i in 0..<12 {
        let angle = CGFloat(i) * (.pi * 2 / 12) - .pi / 2
        let markerDist = faceRadius * 0.82
        let markerPos = CGPoint(x: center.x + cos(angle) * markerDist,
                                 y: center.y + sin(angle) * markerDist)
        let dotSize: CGFloat = (i % 3 == 0) ? size * 0.025 : size * 0.015
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.35, alpha: 0.8))
        ctx.addArc(center: markerPos, radius: dotSize, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
    }

    // Clock hands
    let handColor = CGColor(red: 0.15, green: 0.15, blue: 0.3, alpha: 1.0)
    ctx.setStrokeColor(handColor)
    ctx.setLineCap(.round)

    // Hour hand (pointing to ~10 o'clock)
    let hourAngle: CGFloat = -(.pi / 2) + (.pi * 2 * 10 / 12)
    let hourLen = faceRadius * 0.5
    ctx.setLineWidth(size * 0.03)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(hourAngle) * hourLen,
                             y: center.y + sin(hourAngle) * hourLen))
    ctx.strokePath()

    // Minute hand (pointing to ~2 o'clock / 10 min)
    let minAngle: CGFloat = -(.pi / 2) + (.pi * 2 * 10 / 60)
    let minLen = faceRadius * 0.7
    ctx.setLineWidth(size * 0.02)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(minAngle) * minLen,
                             y: center.y + sin(minAngle) * minLen))
    ctx.strokePath()

    // Center dot
    ctx.setFillColor(handColor)
    ctx.addArc(center: center, radius: size * 0.02, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // Checkmark badge (bottom-right)
    let badgeCenter = CGPoint(x: center.x + size * 0.22, y: center.y - size * 0.22)
    let badgeRadius = size * 0.15

    // Badge circle background (green)
    ctx.setFillColor(CGColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1.0))
    ctx.addArc(center: badgeCenter, radius: badgeRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // White ring
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(size * 0.015)
    ctx.addArc(center: badgeCenter, radius: badgeRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Checkmark
    let checkScale = badgeRadius * 0.5
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(size * 0.025)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let checkStart = CGPoint(x: badgeCenter.x - checkScale * 0.55, y: badgeCenter.y + checkScale * 0.05)
    let checkMid   = CGPoint(x: badgeCenter.x - checkScale * 0.1,  y: badgeCenter.y - checkScale * 0.4)
    let checkEnd   = CGPoint(x: badgeCenter.x + checkScale * 0.6,  y: badgeCenter.y + checkScale * 0.45)

    ctx.move(to: checkStart)
    ctx.addLine(to: checkMid)
    ctx.addLine(to: checkEnd)
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String, pixelSize: Int) {
    let resized = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    resized.unlockFocus()

    guard let tiff = resized.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(path)")
    } catch {
        print("  ✗ Failed: \(error)")
    }
}

// --- Main ---

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x",1024),
]

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let iconsetDir = projectDir
    .appendingPathComponent("WorklogApp/Assets.xcassets/AppIcon.appiconset")

let fm = FileManager.default
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

print("Generating WorklogApp icon...")

let masterImage = drawIcon(size: 1024)

for entry in sizes {
    let path = iconsetDir.appendingPathComponent("\(entry.name).png").path
    savePNG(masterImage, to: path, pixelSize: entry.pixels)
}

// Write Contents.json
let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png",       "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",        "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",     "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",      "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",      "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",      "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

try! contentsJSON.write(to: iconsetDir.appendingPathComponent("Contents.json"),
                        atomically: true, encoding: .utf8)

print("✅ Icon set generated at: \(iconsetDir.path)")
