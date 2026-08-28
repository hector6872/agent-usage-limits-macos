import SwiftUI

/// The horizontal menu bar view showing all enabled AI providers stacked horizontally
public struct MenuBarView: View {
    @ObservedObject var usageManager: UsageManager
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            let active = usageManager.activeUsages
            if active.isEmpty {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                Text("AI")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            } else {
                ForEach(active) { usage in
                    ProviderMenuBarItem(usage: usage)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Individual provider item in the menu bar
struct ProviderMenuBarItem: View {
    let usage: ProviderUsage
    
    var body: some View {
        HStack(spacing: 4) {
            // Brand Logo
            BrandIconView(symbol: usage.iconSymbol, size: 12)
                .opacity(0.9)
            
            // If weekly quota is tracked
            if usage.weeklyWindow.usedPercent > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    // Top line: Session window remaining % with status dot
                    HStack(spacing: 2.5) {
                        Circle()
                            .fill(usage.healthStatus.color)
                            .frame(width: 4.5, height: 4.5)
                        
                        Text("\(Int(usage.shortWindow.remainingPercent))%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    
                    // Bottom line: Weekly window remaining %
                    HStack(spacing: 2) {
                        let weeklyRemaining = Int(usage.weeklyWindow.remainingPercent)
                        if weeklyRemaining < 20 {
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 5.5))
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 5.5))
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(weeklyRemaining)%")
                            .font(.system(size: 8.5, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Single line compact view
                HStack(spacing: 3) {
                    Circle()
                        .fill(usage.healthStatus.color)
                        .frame(width: 5, height: 5)
                    
                    Text("\(Int(usage.shortWindow.remainingPercent))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}
