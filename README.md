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
    public let iconSymbol: String = "sparkles"
    
    public let shortWindowDurationHours: Double = 5.0
    public var isEnabled: Bool = true
    
    public func fetchUsage() async throws -> ProviderUsage {
        let shortReset = Date().addingTimeInterval(3600 * 2.5)
        let weeklyReset = Date().addingTimeInterval(86400 * 3.0)
        
        let shortWindow = QuotaWindow(
            name: "5-hour limit",
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
            weeklyWindow: weeklyWindow
        )
    }
}
```

Then register it in `UsageManager.swift`:
```swift
usageManager.register(provider: CustomAIProvider())
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

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
