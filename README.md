# AI Usage Limits Monitor for macOS 🤖📊

A native, lightweight macOS menu bar application designed to monitor your AI coding assistant usage quotas in real-time (supporting **Antigravity**, **Claude**, **Codex**, and any custom provider via a plugin architecture).

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-green.svg)

---

## 🌟 Features

- **Menu Bar Integration**: Real-time quota tracking for multiple AI providers in a compact horizontal layout.
- **Dual Quota Monitoring**: Tracks rolling session limits (e.g. 5 hours) and weekly quotas with countdown reset timers.
- **Minimalist macOS UI**: Clean, native design with unobtrusive progress bars and detailed popover cards.
- **Multi-Language Support (i18n)**: Out-of-the-box support for **English** and **Spanish** (with automatic system language detection and manual selector).
- **Plugin Architecture**: Modular design to easily add new providers (Antigravity, Claude, Codex, etc.).
- **Lightweight & Native**: Built with Swift 6 and SwiftUI, with zero external dependencies.

---

## 🔌 Plugin Architecture: Adding a New Provider

Implement the `UsageProvider` protocol:

```swift
import Foundation

public final class CustomAIProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "my-ai"
    public let displayName: String = "My AI"
    public let iconSymbol: String = "sparkles" // SF Symbol or custom brand symbol
    
    /// Configurable sliding session window in hours (e.g., 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let shortReset = now.addingTimeInterval(3600 * 2.5)
        let weeklyReset = now.addingTimeInterval(86400 * 3.0)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 15.0,
            resetDate: shortReset
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly · all models",
            windowDurationHours: 168.0,
            usedPercent: 40.0,
            resetDate: weeklyReset
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
```

Then register it in `UsageManager.swift`:
```swift
usageManager.register(provider: CustomAIProvider())
```

---

## 🌐 Localization (i18n): Adding a New Language

Translations are organized using standard Apple `Localizable.strings` files inside `Sources/AgentUsageLimits/Resources/`:

```
Sources/AgentUsageLimits/Resources/
├── en.lproj/Localizable.strings  # English (Default)
├── es.lproj/Localizable.strings  # Spanish
└── fr.lproj/Localizable.strings  # (Example: Adding French)
```

To add a new language:
1. Create a new folder: `Sources/AgentUsageLimits/Resources/<language_code>.lproj/Localizable.strings`.
2. Copy the keys from `en.lproj/Localizable.strings` and translate them.
3. Add the language case in [`LocalizationManager.swift`](Sources/AgentUsageLimits/Services/LocalizationManager.swift):
   ```swift
   public enum AppLanguage: String, CaseIterable, Identifiable {
       case system = "system"
       case english = "en"
       case spanish = "es"
       case french = "fr" // <-- Add here
   }
   ```

---

## 🚀 Building & Running

### Quick Commands

1. **Build & Run**:
   ```bash
   make run
   ```

2. **Package `.app` Bundle**:
   ```bash
   make bundle
   ```

3. **Install to `/Applications`**:
   ```bash
   make install
   ```

---

## 🤝 Contributing
Contributions are welcome! Please check out the [CONTRIBUTING.md](CONTRIBUTING.md) guide for details on how to get started and how to add new provider plugins.

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
