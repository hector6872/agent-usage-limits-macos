import SwiftUI

/// Custom vector shapes for AI provider icons to render crisply in the macOS Menu Bar and Popover
public struct BrandIconView: View {
    public let symbol: String
    public var size: CGFloat = 13
    public var color: Color = .primary
    
    public init(symbol: String, size: CGFloat = 13, color: Color = .primary) {
        self.symbol = symbol
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        Group {
            switch symbol {
            case "antigravity.wave":
                AntigravityWaveShape()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size * 0.85)
            case "claude.sun":
                ClaudeSunShape()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                    .frame(width: size, height: size)
            case "codex.chevron":
                CodexIconShape()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            case "chatgpt.swirl":
                ChatGPTRosetteShape()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
                    .frame(width: size, height: size)
            default:
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(color)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Antigravity chevron / wave logo (peaked wave curve)
struct AntigravityWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.92))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.08),
            control1: CGPoint(x: w * 0.22, y: h * 0.82),
            control2: CGPoint(x: w * 0.36, y: h * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.92),
            control1: CGPoint(x: w * 0.64, y: h * 0.08),
            control2: CGPoint(x: w * 0.78, y: h * 0.82)
        )
        return path
    }
}

/// Claude sunburst / asterisk shape
struct ClaudeSunShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rays = 12
        let innerRadius = rect.width * 0.18
        let outerRadius = rect.width * 0.48
        
        for i in 0..<rays {
            let angle = (Double(i) * (2 * Double.pi / Double(rays)))
            let xStart = center.x + CGFloat(cos(angle)) * innerRadius
            let yStart = center.y + CGFloat(sin(angle)) * innerRadius
            let xEnd = center.x + CGFloat(cos(angle)) * outerRadius
            let yEnd = center.y + CGFloat(sin(angle)) * outerRadius
            
            path.move(to: CGPoint(x: xStart, y: yStart))
            path.addLine(to: CGPoint(x: xEnd, y: yEnd))
        }
        
        path.addEllipse(in: CGRect(
            x: center.x - innerRadius * 0.75,
            y: center.y - innerRadius * 0.75,
            width: innerRadius * 1.5,
            height: innerRadius * 1.5
        ))
        
        return path
    }
}

/// Codex chevron / terminal brackets shape
struct CodexIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Left prompt bracket >
        path.move(to: CGPoint(x: w * 0.12, y: h * 0.22))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.78))
        
        // Cursor line _
        path.move(to: CGPoint(x: w * 0.60, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.78))
        
        return path
    }
}

/// ChatGPT rosette swirl shape
struct ChatGPTRosetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let petals = 6
        let r = rect.width * 0.36
        
        for i in 0..<petals {
            let angle = Double(i) * (2 * Double.pi / Double(petals))
            let pCenter = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (r * 0.5),
                y: center.y + CGFloat(sin(angle)) * (r * 0.5)
            )
            path.addEllipse(in: CGRect(
                x: pCenter.x - r * 0.5,
                y: pCenter.y - r * 0.5,
                width: r,
                height: r
            ))
        }
        return path
    }
}
