#!/usr/bin/env swift
import Cocoa

func drawStar(in context: CGContext, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, fillColor: NSColor) {
    let path = CGMutablePath()
    let points = 4
    for i in 0..<(points * 2) {
        let angle = Double(i) * (.pi / Double(points)) - (.pi / 2.0)
        let r = (i % 2 == 0) ? outerRadius : innerRadius
        let pt = CGPoint(
            x: center.x + CGFloat(cos(angle)) * r,
            y: center.y + CGFloat(sin(angle)) * r
        )
        if i == 0 {
            path.move(to: pt)
        } else {
            path.addLine(to: pt)
        }
    }
    path.closeSubpath()
    
    context.saveGState()
    context.addPath(path)
    context.setFillColor(fillColor.cgColor)
    context.fillPath()
    context.restoreGState()
}

func drawCurvedStar(in context: CGContext, center: CGPoint, radius: CGFloat, gradient: CGGradient) {
    let path = CGMutablePath()
    let r = radius
    let w = r * 0.18 // waist curvature
    
    // Top point
    path.move(to: CGPoint(x: center.x, y: center.y + r))
    // Curve to Right point
    path.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y), control: CGPoint(x: center.x + w, y: center.y + w))
    // Curve to Bottom point
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r), control: CGPoint(x: center.x + w, y: center.y - w))
    // Curve to Left point
    path.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y), control: CGPoint(x: center.x - w, y: center.y - w))
    // Curve back to Top point
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r), control: CGPoint(x: center.x - w, y: center.y + w))
    path.closeSubpath()
    
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: center.x - r, y: center.y + r), end: CGPoint(x: center.x + r, y: center.y - r), options: [])
    context.restoreGState()
    
    // White inner core glow
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
    context.setLineWidth(radius * 0.04)
    context.strokePath()
    context.restoreGState()
}

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.224
    let inset = size * 0.04
    let path = CGPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // 1. Deep Space AI Gradient Background (Obsidian & Indigo to Deep Violet)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(red: 0.18, green: 0.10, blue: 0.32, alpha: 1.0).cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        context.restoreGState()
    }
    
    // Subtle outer glass border
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    context.setLineWidth(size * 0.015)
    context.strokePath()
    context.restoreGState()
    
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    
    // 2. Glowing Token / Quota Meter Ring (Background Track)
    let meterRadius = size * 0.34
    let meterBgPath = CGMutablePath()
    meterBgPath.addArc(center: center, radius: meterRadius, startAngle: -.pi * 0.25, endAngle: .pi * 1.25, clockwise: false)
    
    context.saveGState()
    context.addPath(meterBgPath)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    context.setLineWidth(size * 0.045)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()
    
    // 3. Active Gradient Quota Arc
    let activeMeterPath = CGMutablePath()
    activeMeterPath.addArc(center: center, radius: meterRadius, startAngle: .pi * 0.35, endAngle: .pi * 1.25, clockwise: false)
    
    let meterColors = [
        NSColor(red: 0.0, green: 0.95, blue: 0.75, alpha: 1.0).cgColor,
        NSColor(red: 0.0, green: 0.65, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(red: 0.65, green: 0.3, blue: 0.95, alpha: 1.0).cgColor
    ] as CFArray
    let meterLocations: [CGFloat] = [0.0, 0.5, 1.0]
    
    if let meterGrad = CGGradient(colorsSpace: colorSpace, colors: meterColors, locations: meterLocations) {
        context.saveGState()
        context.addPath(activeMeterPath)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(meterGrad, start: CGPoint(x: center.x - meterRadius, y: center.y), end: CGPoint(x: center.x + meterRadius, y: center.y + meterRadius), options: [])
        context.restoreGState()
    }
    
    // 4. Central AI Sparkle Star (Iridescent Neon Gradient)
    let starColors = [
        NSColor(red: 0.20, green: 0.90, blue: 1.00, alpha: 1.0).cgColor, // Cyan
        NSColor(red: 0.60, green: 0.35, blue: 1.00, alpha: 1.0).cgColor, // Violet
        NSColor(red: 1.00, green: 0.30, blue: 0.65, alpha: 1.0).cgColor  // Coral Pink
    ] as CFArray
    let starLocations: [CGFloat] = [0.0, 0.5, 1.0]
    
    if let starGradient = CGGradient(colorsSpace: colorSpace, colors: starColors, locations: starLocations) {
        // Star Shadow / Glow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.08, color: NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.6).cgColor)
        drawCurvedStar(in: context, center: center, radius: size * 0.22, gradient: starGradient)
        context.restoreGState()
    }
    
    // 5. Satellite Mini Sparkles
    let miniSparkle1 = CGPoint(x: size * 0.74, y: size * 0.72)
    let miniColors = [
        NSColor.white.cgColor,
        NSColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 1.0).cgColor
    ] as CFArray
    if let miniGrad = CGGradient(colorsSpace: colorSpace, colors: miniColors, locations: [0.0, 1.0]) {
        drawCurvedStar(in: context, center: miniSparkle1, radius: size * 0.08, gradient: miniGrad)
    }
    
    let miniSparkle2 = CGPoint(x: size * 0.26, y: size * 0.28)
    if let miniGrad = CGGradient(colorsSpace: colorSpace, colors: miniColors, locations: [0.0, 1.0]) {
        drawCurvedStar(in: context, center: miniSparkle2, radius: size * 0.05, gradient: miniGrad)
    }
    
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

print("AI Iconset generated successfully at \(iconsetDir)")
