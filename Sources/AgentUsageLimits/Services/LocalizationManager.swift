import Foundation
import SwiftUI
import Combine

/// Supported application languages
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system:
            return "System / Sistema"
        case .english:
            return "English"
        case .spanish:
            return "Español"
        }
    }
}

/// Central Localization Manager that loads standard Localizable.strings from SPM resource bundles
@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    @AppStorage("selected_app_language") private var storedLanguage: String = AppLanguage.system.rawValue
    
    @Published public var currentLanguage: AppLanguage = .system {
        didSet {
            storedLanguage = currentLanguage.rawValue
            updateActiveBundle()
        }
    }
    
    private var activeBundle: Bundle = Bundle.module
    
    public init() {
        if let lang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "selected_app_language") ?? "system") {
            self.currentLanguage = lang
        }
        updateActiveBundle()
    }
    
    /// Resolved language code ("en" or "es")
    public var resolvedCode: String {
        switch currentLanguage {
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.starts(with: "es") {
                return "es"
            }
            return "en"
        }
    }
    
    private func updateActiveBundle() {
        let code = resolvedCode
        if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.activeBundle = bundle
        } else {
            self.activeBundle = Bundle.module
        }
    }
    
    /// Generic string localization helper from Localizable.strings
    public func string(forKey key: String, _ args: CVarArg...) -> String {
        let format = activeBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if args.isEmpty {
            return format
        }
        return String(format: format, locale: Locale(identifier: resolvedCode), arguments: args)
    }
    
    // MARK: - Convenient Accessors
    
    public func yourUsageLimits(provider: String) -> String {
        string(forKey: "usage_limits_header", provider.uppercased())
    }
    
    public func shortLimitTitle(hours: Int) -> String {
        string(forKey: "short_limit_title", hours)
    }
    
    public var weeklyLimitTitle: String {
        string(forKey: "weekly_limit_title")
    }
    
    public func resetsFormatted(interval: TimeInterval) -> String {
        if interval <= 0 {
            return string(forKey: "resets_soon")
        }
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if days > 0 {
            return string(forKey: "resets_days", days)
        } else if hours > 0 {
            return string(forKey: "resets_hours", hours)
        } else {
            return string(forKey: "resets_minutes", max(1, minutes))
        }
    }
    
    public var refresh: String {
        string(forKey: "refresh")
    }
    
    public var updatedJustNow: String {
        string(forKey: "updated_just_now")
    }
    
    public func updatedSecondsAgo(_ s: Int) -> String {
        string(forKey: "updated_seconds_ago", s)
    }
    
    public func updatedMinutesAgo(_ m: Int) -> String {
        string(forKey: "updated_minutes_ago", m)
    }
    
    public var providersHeader: String {
        string(forKey: "providers_header")
    }
    
    public var refreshInterval: String {
        string(forKey: "refresh_interval")
    }
    
    public var languageLabel: String {
        string(forKey: "language_label")
    }
    
    public var quitApp: String {
        string(forKey: "quit_app")
    }
    
    public var noActiveProviders: String {
        string(forKey: "no_active_providers")
    }
    
    public var enableProvidersInSettings: String {
        string(forKey: "enable_providers_in_settings")
    }
}
