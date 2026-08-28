import Foundation

/// Protocol that all AI quota providers (Claude, Antigravity, ChatGPT, Cursor, etc.) must implement.
public protocol UsageProvider: Sendable {
    /// Unique identifier for the provider (e.g., "claude", "antigravity")
    var id: String { get }
    
    /// User-facing display name (e.g., "Claude Code", "Google Antigravity")
    var displayName: String { get }
    
    /// Icon identifier (system SF symbol or custom identifier)
    var iconSymbol: String { get }
    
    /// Configurable duration for the short sliding session window in hours (e.g. 5.0 hours)
    var shortWindowDurationHours: Double { get }
    
    /// Whether this provider is enabled to fetch and display in menu bar
    var isEnabled: Bool { get set }
    
    /// Fetches the latest quota usage information asynchronously
    func fetchUsage() async throws -> ProviderUsage
}
