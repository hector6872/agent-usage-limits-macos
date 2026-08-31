# Contributing to agent-usage-limits-macos 🤝

Thank you for your interest in contributing to **agent-usage-limits-macos**! We welcome contributions of all kinds, whether it's adding new AI quota providers, improving the UI, adding translations, fixing bugs, or improving documentation.

---

## 🛠 Development Workflow

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 15+ command-line tools (`swift --version` >= 6.0 / 5.10)
- Git

### Quick Start
```bash
git clone https://github.com/hector6872/agent-usage-limits-macos.git
cd agent-usage-limits-macos

# Compile and launch in development mode
make dev
```

---

## 🔌 Adding a New Provider Plugin

Adding support for a new AI assistant (e.g. Cursor, DeepSeek, Ollama, OpenRouter, Copilot) is designed to be modular and straightforward:

### Step 1: Create the Provider File
Create a new file in `Sources/AgentUsageLimits/Providers/YourProviderUsageProvider.swift`.

### Step 2: Implement the `UsageProvider` Protocol
Implement the required protocol properties, process detection (`isActive`), and the `fetchUsage()` async method:

```swift
import Foundation
import AppKit

public final class YourProviderUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "your-provider-id"
    public let displayName: String = "Your Provider"
    public let iconSymbol: String = "sparkles" // SF Symbol name or custom brand symbol
    
    /// Configurable sliding session window in hours (e.g., 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    /// Check whether the provider application or CLI is currently running
    public var isActive: Bool {
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return bundleId.contains("your-provider") || name.contains("your-provider")
        }
        return isAppRunning
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let active = self.isActive
        
        guard active else {
            return ProviderUsage(
                providerId: id,
                displayName: displayName,
                iconSymbol: iconSymbol,
                isActive: false,
                shortWindow: QuotaWindow(name: "\(Int(shortWindowDurationHours))-hour limit", windowDurationHours: shortWindowDurationHours, usedPercent: 0),
                weeklyWindow: QuotaWindow(name: "Weekly", windowDurationHours: 168.0, usedPercent: 0),
                showWeeklyInMenuBar: true,
                lastUpdated: now
            )
        }
        
        // 1. Fetch live quota data from your local client, config file, CLI cache, or API
        let shortResetDate = now.addingTimeInterval(3600 * 2.5) // Example: resets in 2.5h
        let weeklyResetDate = now.addingTimeInterval(86400 * 4.0) // Example: resets in 4 days
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 18.0, // 18% used
            resetDate: shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 32.0, // 32% used
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
```

### Step 3: Register the Provider in `UsageManager`
Add your new provider to the default providers array in [`UsageManager.swift`](Sources/AgentUsageLimits/Services/UsageManager.swift):

```swift
public init(providers: [any UsageProvider] = []) {
    if providers.isEmpty {
        self.providers = [
            AntigravityUsageProvider(),
            ClaudeUsageProvider(),
            CodexUsageProvider(),
            YourProviderUsageProvider() // <-- Add here
        ]
    } else {
        self.providers = providers
    }
    // ...
}
```

Or dynamically at runtime via:
```swift
usageManager.register(provider: YourProviderUsageProvider())
```

### Step 4: (Optional) Add a Custom Brand Vector Icon
If your provider has a unique logo, define its vector shape in [`BrandIcons.swift`](Sources/AgentUsageLimits/Views/BrandIcons.swift):

```swift
case "your-provider-symbol":
    YourCustomShape()
        .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
        .frame(width: size, height: size)
```

---

## 🌐 Contributing Translations

All user-facing strings are localized using standard Apple `.strings` files in `Sources/AgentUsageLimits/Resources/`:

```
Sources/AgentUsageLimits/Resources/
├── en.lproj/Localizable.strings
├── es.lproj/Localizable.strings
├── fr.lproj/Localizable.strings
├── de.lproj/Localizable.strings
├── it.lproj/Localizable.strings
├── pt.lproj/Localizable.strings
├── ja.lproj/Localizable.strings
├── zh-Hans.lproj/Localizable.strings
├── ko.lproj/Localizable.strings
└── <lang>.lproj/Localizable.strings
```

To add a new language:
1. Create `Sources/AgentUsageLimits/Resources/<lang_code>.lproj/Localizable.strings`.
2. Copy the key-value pairs from `en.lproj/Localizable.strings` and translate them.
3. Add the language case to `AppLanguage` in [`LocalizationManager.swift`](Sources/AgentUsageLimits/Services/LocalizationManager.swift):
   ```swift
   public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
       case system = "system"
       case english = "en"
       case spanish = "es"
       // ...
       case newLang = "code" // <-- Add here
   }
   ```

---

## 📜 Code of Conduct

Please be respectful, constructive, and welcoming in all discussions and pull requests.
