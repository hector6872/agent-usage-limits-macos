import SwiftUI

/// The horizontal menu bar view showing active AI providers with adaptive Light/Dark mode typography
public struct MenuBarView: View {
    @ObservedObject var usageManager: UsageManager
    public var isDarkMode: Bool = true
    
    public init(usageManager: UsageManager, isDarkMode: Bool = true) {
        self.usageManager = usageManager
        self.isDarkMode = isDarkMode
    }
    
    private var primaryColor: Color {
        isDarkMode ? .white : .black
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            let active = usageManager.activeUsages
            if active.isEmpty {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 11))
                    .foregroundColor(primaryColor)
                Text("AI")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryColor)
            } else {
                ForEach(active) { usage in
                    ProviderMenuBarItem(usage: usage, isDarkMode: isDarkMode)
                }
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
        .frame(height: 22)
    }
}

/// Individual provider item in the menu bar with strict tabular alignment and 0% red highlight
struct ProviderMenuBarItem: View {
    let usage: ProviderUsage
    let isDarkMode: Bool
    
    private var primaryColor: Color {
        isDarkMode ? .white : .black
    }
    
    var body: some View {
        if usage.showWeeklyInMenuBar {
            // Dual-line layout: Icon + [Dot / W column] + [Right-aligned % column]
            HStack(alignment: .center, spacing: 3.5) {
                // 1. Vertically centered Brand Icon
                BrandIconView(symbol: usage.iconSymbol, size: 12.5, color: primaryColor)
                
                // 2. Indicators Column (Centered Dot & Centered W)
                VStack(alignment: .center, spacing: 1) {
                    Circle()
                        .fill(usage.shortWindow.healthStatus.color)
                        .frame(width: 4.5, height: 4.5)
                        .frame(width: 8, height: 9.5, alignment: .center)
                    
                    Text("W")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(usage.weeklyWindow.healthStatus.color)
                        .frame(width: 8, height: 9.5, alignment: .center)
                }
                
                // 3. Percentages Column (Trailing-aligned numbers; turns red if 0%)
                VStack(alignment: .trailing, spacing: 1) {
                    let shortRemaining = Int(usage.shortWindow.remainingPercent)
                    Text("\(shortRemaining)%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(shortRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
                        .frame(height: 9.5, alignment: .trailing)
                    
                    let weeklyRemaining = Int(usage.weeklyWindow.remainingPercent)
                    Text("\(weeklyRemaining)%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(weeklyRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
                        .frame(height: 9.5, alignment: .trailing)
                }
            }
        } else {
            // Single-line hero layout (like Antigravity in reference image: Icon + Dot + 46%)
            HStack(spacing: 4) {
                BrandIconView(symbol: usage.iconSymbol, size: 13, color: primaryColor)
                
                Circle()
                    .fill(usage.shortWindow.healthStatus.color)
                    .frame(width: 5, height: 5)
                
                let shortRemaining = Int(usage.shortWindow.remainingPercent)
                Text("\(shortRemaining)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(shortRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
            }
        }
    }
}
