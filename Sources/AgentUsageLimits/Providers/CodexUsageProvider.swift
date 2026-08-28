import Foundation

/// Provider for OpenAI Codex / GitHub Copilot Codex quotas
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
        let shortResetDate = now.addingTimeInterval(3600 * 2.0) // resets in ~2h
        let weeklyResetDate = now.addingTimeInterval(86400 * 1.2) // resets in ~1d
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 2.0, // 2% used, 98% remaining
            usedUnits: 10,
            totalUnits: 500,
            unitLabel: "reqs",
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly · all models",
            windowDurationHours: 168.0,
            usedPercent: 11.0, // 11% used, 89% remaining
            usedUnits: 550,
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
            lastUpdated: now
        )
    }
}
