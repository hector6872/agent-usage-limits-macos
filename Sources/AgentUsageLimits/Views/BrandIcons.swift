import SwiftUI

/// Custom vector shapes for AI provider icons to render crisply in the macOS Menu Bar and Popover
public struct BrandIconView: View {
    public let symbol: String
    public var size: CGFloat = 13
    
    public init(symbol: String, size: CGFloat = 13) {
        self.symbol = symbol
        self.size = size
    }
    
    public var body: some View {
        Group {
            switch symbol {
            case "antigravity.wave":
                AntigravityWaveShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size * 0.85)
            case "claude.sun":
                ClaudeSunShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .frame(width: size, height: size)
            case "codex.chevron":
                CodexIconShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            default:
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Antigravity chevron / wave logo
struct AntigravityWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.05, y: h * 0.95))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.1),
            control1: CGPoint(x: w * 0.2, y: h * 0.85),
            control2: CGPoint(x: w * 0.35, y: h * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.95),
            control1: CGPoint(x: w * 0.65, y: h * 0.1),
            control2: CGPoint(x: w * 0.8, y: h * 0.85)
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
        let innerRadius = rect.width * 0.2
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
            x: center.x - innerRadius * 0.7,
            y: center.y - innerRadius * 0.7,
            width: innerRadius * 1.4,
            height: innerRadius * 1.4
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
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.75))
        
        // Cursor line _
        path.move(to: CGPoint(x: w * 0.58, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.75))
        
        return path
    }
}
