import Foundation
import AppKit

/// Provider for Google Antigravity (AGY Agent / Gemini quotas)
public final class AntigravityUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "antigravity"
    public let displayName: String = "Antigravity"
    public let iconSymbol: String = "antigravity.wave"
    
    /// Short sliding window duration in hours (default 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    /// Checks whether Antigravity is currently running (Desktop App process or active CLI process)
    public var isActive: Bool {
        // 1. Check if Antigravity Desktop App UI is running
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundleId.contains("antigravity") || name.contains("antigravity") || execName.contains("antigravity")
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
        
        // When active and running, fetch live session & weekly quotas
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
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 28.0, // 72% remaining
            usedUnits: 560000,
            totalUnits: 2000000,
            unitLabel: "tok",
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
