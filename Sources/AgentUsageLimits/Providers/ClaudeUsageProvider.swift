import Foundation

/// Provider for Anthropic Claude (Claude Code / Claude Pro & Team quotas)
public final class ClaudeUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "claude"
    public let displayName: String = "Claude"
    public let iconSymbol: String = "claude.sun"
    
    /// Short sliding window duration in hours (Claude typical limit is 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let shortResetDate = now.addingTimeInterval(3600 * 2.2)
        let weeklyResetDate = now.addingTimeInterval(86400 * 3.4)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 58.0, // 42% remaining
            usedUnits: 290,
            totalUnits: 500,
            unitLabel: "msgs",
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 7.0, // 93% remaining
            usedUnits: 350,
            totalUnits: 5000,
            unitLabel: "msgs",
            resetDate: weeklyResetDate
        )
        
        return ProviderUsage(
            providerId: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: true,
            lastUpdated: now
        )
    }
}
