import Foundation
import SwiftUI

/// Status of the quota health
public enum HealthStatus: String, Codable, Sendable {
    case healthy    // Plenty of quota remaining (> 30%)
    case warning    // Approaching limit (10% - 30%)
    case critical   // Very low or depleted (< 10%)
    case unknown    // Unable to fetch or offline

    public var color: Color {
        switch self {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .gray
        }
    }
}

/// Represents a specific usage quota window (e.g., 5-hour rolling session or weekly allocation)
public struct QuotaWindow: Identifiable, Codable, Sendable {
    public var id: String { name }
    
    /// Title / label of this window (e.g. "5-hour limit", "Weekly · all models")
    public let name: String
    
    /// Configured window duration in hours (e.g. 5.0 for a 5-hour window, 168.0 for weekly)
    public let windowDurationHours: Double?
    
    /// Percentage used (0.0 to 100.0)
    public let usedPercent: Double
    
    /// Percentage remaining (0.0 to 100.0)
    public var remainingPercent: Double {
        max(0.0, min(100.0, 100.0 - usedPercent))
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

    /// Compact format matching the UI: "resets 2h", "resets 1d", "resets 45m"
    public var resetsFormatted: String {
        guard let resetDate = resetDate else { return "resets soon" }
        let now = Date()
        let interval = resetDate.timeIntervalSince(now)
        
        if interval <= 0 {
            return "resets soon"
        }
        
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if days > 0 {
            return "resets \(days)d"
        } else if hours > 0 {
            return "resets \(hours)h"
        } else {
            return "resets \(max(1, minutes))m"
        }
    }
    
    /// Extended readable countdown
    public var timeRemainingFormatted: String {
        guard let resetDate = resetDate else { return "Unknown" }
        let now = Date()
        let interval = resetDate.timeIntervalSince(now)
        
        if interval <= 0 {
            return "Resetting soon"
        }
        
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
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
    
    public let lastUpdated: Date
    public let errorMessage: String?

    public init(
        providerId: String,
        displayName: String,
        iconSymbol: String,
        shortWindow: QuotaWindow,
        weeklyWindow: QuotaWindow,
        lastUpdated: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.iconSymbol = iconSymbol
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
    }

    /// Overall health status derived from remaining quota on the short window
    public var healthStatus: HealthStatus {
        if errorMessage != nil { return .unknown }
        let remaining = shortWindow.remainingPercent
        if remaining > 30.0 {
            return .healthy
        } else if remaining > 10.0 {
            return .warning
        } else {
            return .critical
        }
    }
}
