import Foundation
import SwiftUI
import Combine

/// Supported application languages
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    
    public var id: String { rawValue }
    
    @MainActor
    public func localizedName(with l10n: LocalizationManager = .shared) -> String {
        switch self {
        case .system:
            return l10n["language_system"]
        case .english:
            return "English"
        case .spanish:
            return "Español"
        }
    }
}

/// Central Localization Manager that handles bundle resolution and standard Foundation date/time formatters.
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
    
    private lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
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
    
    // MARK: - Idiomatic Localization Access
    
    /// Look up a localized string with optional format arguments
    public func string(_ key: String, _ args: CVarArg...) -> String {
        let format = activeBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if args.isEmpty {
            return format
        }
        return String(format: format, locale: Locale(identifier: resolvedCode), arguments: args)
    }
    
    /// Subscript shorthand: `l10n["refresh"]`
    public subscript(key: String) -> String {
        string(key)
    }
    
    // MARK: - Native Foundation Formatters
    
    /// Relative time ago formatter using Foundation's RelativeDateTimeFormatter
    public func timeAgo(since date: Date) -> String {
        let seconds = abs(date.timeIntervalSinceNow)
        if seconds < 10 {
            return string("updated_just_now")
        }
        relativeDateFormatter.locale = Locale(identifier: resolvedCode)
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Formats countdown remaining time for quota resets (e.g. "resets 2h", "reinicia en 2h")
    public func resetsCountdown(until date: Date?) -> String {
        guard let date = date else { return string("resets_soon") }
        let interval = date.timeIntervalSinceNow
        let prefix = string("resets_prefix")
        
        if interval <= 0 {
            return "\(prefix) <1m"
        }
        
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if days > 0 {
            return "\(prefix) \(days)d"
        } else if hours > 0 {
            return "\(prefix) \(hours)h"
        } else if minutes > 0 {
            return "\(prefix) \(minutes)m"
        } else {
            return "\(prefix) <1m"
        }
    }
}
