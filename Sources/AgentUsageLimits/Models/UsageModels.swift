import Foundation
import SwiftUI

/// Status of the quota health based on remaining percentage
public enum HealthStatus: String, Codable, Sendable {
    case healthy    // > 60% remaining (Green)
    case warning    // 25% - 60% remaining (Yellow)
    case critical   // < 25% remaining (Red)
    case unknown    // Unable to fetch or offline

    public var color: Color {
        switch self {
        case .healthy:
            return Color(red: 0.20, green: 0.84, blue: 0.29) // Vivid Green
        case .warning:
            return Color(red: 1.00, green: 0.80, blue: 0.00) // Vivid Yellow
        case .critical:
            return Color(red: 1.00, green: 0.27, blue: 0.23) // Vivid Red
        case .unknown:
            return .gray
        }
    }
    
    public static func status(for remainingPercent: Double) -> HealthStatus {
        if remainingPercent > 60.0 {
            return .healthy
        } else if remainingPercent >= 25.0 {
            return .warning
        } else {
            return .critical
        }
    }
}

/// Represents a specific usage quota window (e.g., 5-hour rolling session or weekly allocation)
public struct QuotaWindow: Identifiable, Codable, Sendable {
    public var id: String { name }
    
    /// Title / label of this window (e.g. "5-hour limit", "Weekly")
    public let name: String
    
    /// Configured window duration in hours (e.g. 5.0 for a 5-hour window, 168.0 for weekly)
    public let windowDurationHours: Double?
    
    /// Percentage used (0.0 to 100.0)
    public let usedPercent: Double
    
    /// Percentage remaining (0.0 to 100.0)
    public var remainingPercent: Double {
        max(0.0, min(100.0, 100.0 - usedPercent))
    }
    
    /// Health status derived from remaining percentage (>60% green, 25-60% yellow, <25% red)
    public var healthStatus: HealthStatus {
        HealthStatus.status(for: remainingPercent)
    }
    
    /// Optional absolute count (e.g., tokens or prompt requests)
    public let usedUnits: Double?
    public let totalUnits: Double?
    public let unitLabel: String?
    
    /// Target date when this quota window resets
    public let resetDate: Date?

    public init(
        name: String,
        windowDurationHours: Double? = nil,
        usedPercent: Double,
        usedUnits: Double? = nil,
        totalUnits: Double? = nil,
        unitLabel: String? = nil,
        resetDate: Date? = nil
    ) {
        self.name = name
        self.windowDurationHours = windowDurationHours
        self.usedPercent = max(0.0, min(100.0, usedPercent))
        self.usedUnits = usedUnits
        self.totalUnits = totalUnits
        self.unitLabel = unitLabel
        self.resetDate = resetDate
    }

    /// Localized countdown string for quota resets
    @MainActor
    public var localizedResetsFormatted: String {
        LocalizationManager.shared.resetsCountdown(until: resetDate)
    }
    
    /// Localized title if matching standard window types
    @MainActor
    public var localizedTitle: String {
        if let hours = windowDurationHours, hours < 24 {
            let hoursStr = hours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(hours))" : String(format: "%.1f", hours)
            return LocalizationManager.shared.string("short_limit_title", hoursStr)
        } else if windowDurationHours == 168.0 || name.lowercased().contains("weekly") || name.lowercased().contains("semanal") {
            return LocalizationManager.shared["weekly_limit_title"]
        }
        return name
    }
}

/// Aggregated usage data for a single provider
public struct ProviderUsage: Identifiable, Sendable {
    public var id: String { providerId }
    
    public let providerId: String
    public let displayName: String
    public let iconSymbol: String
    
    /// Short-term sliding/session window (default 5h or configured by provider)
    public let shortWindow: QuotaWindow
    
    /// Long-term weekly window
    public let weeklyWindow: QuotaWindow
    
    /// Whether to display the dual-line weekly metric in the compact menu bar
    public let showWeeklyInMenuBar: Bool
    
    public let lastUpdated: Date
    public let errorMessage: String?

    public init(
        providerId: String,
        displayName: String,
        iconSymbol: String,
        shortWindow: QuotaWindow,
        weeklyWindow: QuotaWindow,
        showWeeklyInMenuBar: Bool = true,
        lastUpdated: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.iconSymbol = iconSymbol
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.showWeeklyInMenuBar = showWeeklyInMenuBar
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
    }

    /// Overall health status derived from remaining quota on the short window
    public var healthStatus: HealthStatus {
        if errorMessage != nil { return .unknown }
        return shortWindow.healthStatus
    }
}
