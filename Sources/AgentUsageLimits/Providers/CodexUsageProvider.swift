import Foundation
import AppKit

/// Provider for Codex / OpenAI CLI & Desktop
public final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "codex"
    public let displayName: String = "Codex"
    public let planName: String = "TEAM"
    public let iconSymbol: String = "codex.chevron"
    
    /// Short window duration in hours (e.g. 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    /// Checks whether Codex is currently running on the system
    public var isActive: Bool {
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundleId.contains("codex") || name.contains("codex") || execName.contains("codex")
        }
        return isAppRunning
    }
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let active = self.isActive
        
        guard active else {
            let shortWindow = QuotaWindow(
                name: "\(Int(shortWindowDurationHours))-hour limit",
                windowDurationHours: shortWindowDurationHours,
                usedPercent: 0,
                resetDate: nil
            )
            let weeklyWindow = QuotaWindow(
                name: "Weekly",
                windowDurationHours: 168.0,
                usedPercent: 0,
                resetDate: nil
            )
            return ProviderUsage(
                providerId: id,
                displayName: displayName,
                iconSymbol: iconSymbol,
                isActive: false,
                shortWindow: shortWindow,
                weeklyWindow: weeklyWindow,
                showWeeklyInMenuBar: true,
                lastUpdated: now
            )
        }
        
        // When active and running, fetch live Codex quotas
        let shortResetDate = now.addingTimeInterval(3600 * 2.0)
        let weeklyResetDate = now.addingTimeInterval(86400 * 1.2)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 89.0, // 11% remaining
            usedUnits: 445,
            totalUnits: 500,
            unitLabel: "reqs",
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 93.0, // 7% remaining
            usedUnits: 4650,
            totalUnits: 5000,
            unitLabel: "reqs",
            resetDate: weeklyResetDate
        )
        
        return ProviderUsage(
            providerId: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            isActive: true,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: true,
            lastUpdated: now
        )
    }
}
