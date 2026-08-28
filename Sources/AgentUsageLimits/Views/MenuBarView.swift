import SwiftUI

/// The horizontal menu bar view matching the exact layout of the reference image
public struct MenuBarView: View {
    @ObservedObject var usageManager: UsageManager
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            let active = usageManager.activeUsages
            if active.isEmpty {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 11))
                Text("AI")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            } else {
                ForEach(active) { usage in
                    ProviderMenuBarItem(usage: usage)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.14))
        )
    }
}

/// Individual provider item in the menu bar
struct ProviderMenuBarItem: View {
    let usage: ProviderUsage
    
    var body: some View {
        if usage.showWeeklyInMenuBar {
            // Dual-line layout: Icon with sub-index "1" on the left, stacked percentages on the right
            HStack(alignment: .center, spacing: 3.5) {
                // Left column: Icon + tiny subscript index "1"
                VStack(alignment: .center, spacing: 0.5) {
                    BrandIconView(symbol: usage.iconSymbol, size: 12)
                    
                    Text("1")
                        .font(.system(size: 7, weight: .regular, design: .rounded))
                        .foregroundColor(.primary.opacity(0.8))
                }
                
                // Right column: Top session % (with dot) & Bottom weekly % (with triangle arrow)
                VStack(alignment: .leading, spacing: 0) {
                    // Top: Session remaining % with health dot
                    HStack(spacing: 2.5) {
                        Circle()
                            .fill(usage.healthStatus.color)
                            .frame(width: 4.5, height: 4.5)
                        
                        Text("\(Int(usage.shortWindow.remainingPercent))%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    
                    // Bottom: Weekly % with directional triangle indicator
                    HStack(spacing: 2) {
                        let weeklyRemaining = Int(usage.weeklyWindow.remainingPercent)
                        if weeklyRemaining <= 15 {
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 5))
                                .foregroundColor(.red)
                            Text("\(weeklyRemaining)%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        } else {
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 5))
                                .foregroundColor(.green)
                            Text("\(Int(usage.weeklyWindow.usedPercent))%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        } else {
            // Single-line hero layout (like Antigravity in reference image: Icon + Dot + 46%)
            HStack(spacing: 4) {
                BrandIconView(symbol: usage.iconSymbol, size: 13)
                
                Circle()
                    .fill(usage.healthStatus.color)
                    .frame(width: 5, height: 5)
                
                Text("\(Int(usage.shortWindow.remainingPercent))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}
