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

/// Individual provider item in the menu bar with strict tabular alignment, inactive state, and 0% red highlight
struct ProviderMenuBarItem: View {
    let usage: ProviderUsage
    let isDarkMode: Bool
    
    private var primaryColor: Color {
        isDarkMode ? .white : .black
    }
    
    private var inactiveColor: Color {
        primaryColor.opacity(0.38)
    }
    
    var body: some View {
        if usage.showWeeklyInMenuBar {
            // Dual-line layout: Icon + [Dot / W column] + [Right-aligned % column]
            HStack(alignment: .center, spacing: 3.5) {
                // 1. Vertically centered Brand Icon
                BrandIconView(
                    symbol: usage.iconSymbol,
                    size: 12.5,
                    color: usage.isActive ? primaryColor : inactiveColor
                )
                
                // 2. Indicators Column (Centered W & Centered Dot)
                VStack(alignment: .center, spacing: 1) {
                    Text("W")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(usage.isActive ? usage.weeklyWindow.healthStatus.color : Color.gray.opacity(0.45))
                        .frame(width: 8, height: 9.5, alignment: .center)
                    
                    Circle()
                        .fill(usage.isActive ? usage.shortWindow.healthStatus.color : Color.gray.opacity(0.45))
                        .frame(width: 4.5, height: 4.5)
                        .frame(width: 8, height: 9.5, alignment: .center)
                }
                
                // 3. Percentages Column (Trailing-aligned numbers; turns red if 0%, --% if inactive)
                VStack(alignment: .trailing, spacing: 1) {
                    if usage.isActive {
                        let weeklyRemaining = usage.weeklyWindow.roundedRemainingPercent
                        Text("\(weeklyRemaining)%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(weeklyRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
                            .frame(height: 9.5, alignment: .trailing)
                        
                        let shortRemaining = usage.shortWindow.roundedRemainingPercent
                        Text("\(shortRemaining)%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(shortRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
                            .frame(height: 9.5, alignment: .trailing)
                    } else {
                        Text("--%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(inactiveColor)
                            .frame(height: 9.5, alignment: .trailing)
                        
                        Text("--%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(inactiveColor)
                            .frame(height: 9.5, alignment: .trailing)
                    }
                }
            }
        } else {
            // Single-line hero layout (like Antigravity in reference image: Icon + Dot + 46%)
            HStack(spacing: 4) {
                BrandIconView(
                    symbol: usage.iconSymbol,
                    size: 13,
                    color: usage.isActive ? primaryColor : inactiveColor
                )
                
                Circle()
                    .fill(usage.isActive ? usage.shortWindow.healthStatus.color : Color.gray.opacity(0.45))
                    .frame(width: 5, height: 5)
                
                if usage.isActive {
                    let shortRemaining = usage.shortWindow.roundedRemainingPercent
                    Text("\(shortRemaining)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(shortRemaining <= 0 ? HealthStatus.critical.color : primaryColor)
                } else {
                    Text("--%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(inactiveColor)
                }
            }
        }
    }
}
