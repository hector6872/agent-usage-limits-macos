#!/usr/bin/env swift
import Cocoa

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.05, dy: size * 0.05), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Background gradient (Deep AI Indigo to Neon Cyan)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.08, green: 0.12, blue: 0.28, alpha: 1.0).cgColor,
        NSColor(red: 0.12, green: 0.38, blue: 0.72, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.75, blue: 0.65, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.6, 1.0]
    
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        context.restoreGState()
    }
    
    // Draw outer subtle border
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    context.setLineWidth(size * 0.02)
    context.strokePath()
    context.restoreGState()
    
    // Draw Gauge Arc
    let center = CGPoint(x: size * 0.5, y: size * 0.52)
    let radius = size * 0.28
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: radius, startAngle: -.pi * 0.2, endAngle: .pi * 1.2, clockwise: false)
    
    context.saveGState()
    context.addPath(arcPath)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    context.setLineWidth(size * 0.06)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()
    
    // Active Gauge Arc (Green neon)
    let activeArc = CGMutablePath()
    activeArc.addArc(center: center, radius: radius, startAngle: .pi * 0.3, endAngle: .pi * 1.2, clockwise: false)
    
    context.saveGState()
    context.addPath(activeArc)
    context.setStrokeColor(NSColor(red: 0.3, green: 0.95, blue: 0.6, alpha: 1.0).cgColor)
    context.setLineWidth(size * 0.06)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()
    
    // Draw AI Sparkle / Percentage symbol in center
    let percentText = "%"
    let font = NSFont.systemFont(ofSize: size * 0.28, weight: .black)
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let attrString = NSAttributedString(string: percentText, attributes: textAttributes)
    let textSize = attrString.size()
    let textOrigin = CGPoint(
        x: center.x - textSize.width * 0.5,
        y: center.y - textSize.height * 0.5
    )
    attrString.draw(at: textOrigin)
    
    // Sparkles on top right
    let sparkleRadius = size * 0.04
    let sparkleCenter = CGPoint(x: size * 0.72, y: size * 0.72)
    context.saveGState()
    context.setFillColor(NSColor.white.cgColor)
    context.fillEllipse(in: CGRect(x: sparkleCenter.x - sparkleRadius, y: sparkleCenter.y - sparkleRadius, width: sparkleRadius * 2, height: sparkleRadius * 2))
    context.restoreGState()
    
    image.unlockFocus()
    return image
}

let iconsetDir = "resources/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in sizes {
    let img = createIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let path = "\(iconsetDir)/\(filename)"
        try? pngData.write(to: URL(fileURLWithPath: path))
    }
}

print("Iconset generated successfully at \(iconsetDir)")
