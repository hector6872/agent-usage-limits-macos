import Foundation

/// Provider for Google Antigravity (AGY Agent / Gemini quotas)
public final class AntigravityUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "antigravity"
    public let displayName: String = "Antigravity"
    public let iconSymbol: String = "antigravity.wave"
    
    /// Short sliding window duration in hours (default 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let shortResetDate = now.addingTimeInterval(3600 * 3.0)
        let weeklyResetDate = now.addingTimeInterval(86400 * 5.1)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 54.0, // 46% remaining
            usedUnits: 92000,
            totalUnits: 200000,
            unitLabel: "tok",
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly · all models",
            windowDurationHours: 168.0,
            usedPercent: 28.0,
            usedUnits: 560000,
            totalUnits: 2000000,
            unitLabel: "tok",
            resetDate: weeklyResetDate
        )
        
        return ProviderUsage(
            providerId: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: false, // Matches reference screenshot (single line)
            lastUpdated: now
        )
    }
}
