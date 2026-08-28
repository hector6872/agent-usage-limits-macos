import Foundation

/// Provider for Codex quotas
public final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "codex"
    public let displayName: String = "Codex"
    public let planName: String = "TEAM"
    public let iconSymbol: String = "codex.chevron"
    
    /// Short window duration in hours (e.g. 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let shortResetDate = now.addingTimeInterval(3600 * 2.0)
        let weeklyResetDate = now.addingTimeInterval(86400 * 1.2)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 100.0, // 0% remaining (Red dot + Red 0%)
            usedUnits: 500,
            totalUnits: 500,
            unitLabel: "reqs",
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 100.0, // 0% remaining (Red W + Red 0%)
            usedUnits: 5000,
            totalUnits: 5000,
            unitLabel: "reqs",
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
