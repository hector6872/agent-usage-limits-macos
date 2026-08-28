# Contributing to AI Usage Limits Monitor 🤝

Thank you for your interest in contributing to **AI Usage Limits Monitor for macOS**! We welcome contributions of all kinds, whether it's adding new AI quota providers, improving the UI, fixing bugs, or writing documentation.

---

## 🛠 Development Workflow

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 15+ command-line tools (`swift --version` >= 6.0 / 5.10)
- Git

### Getting Started

1. **Fork & Clone** the repository:
   ```bash
   git clone https://github.com/hector6872/agent-usage-limits-macos.git
   cd agent-usage-limits-macos
   ```

2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/my-new-provider
   ```

3. **Build and Test**:
   ```bash
   # Build the project
   make build

   # Build and launch the menu bar app
   make run
   ```

---

## 🔌 Adding a New Provider Plugin

Adding support for a new AI assistant (e.g. Cursor, DeepSeek, Ollama, OpenRouter) is straightforward:

1. Create a new file in `Sources/AgentUsageLimits/Providers/YourProviderUsageProvider.swift`.
2. Implement the `UsageProvider` protocol:

```swift
import Foundation

public final class YourProviderUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "your-provider-id"
    public let displayName: String = "Your Provider"
    public let iconSymbol: String = "sparkles" // SF Symbol or custom vector
    
    // Configurable rolling session window (e.g. 5.0 hours)
    public let shortWindowDurationHours: Double = 5.0
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    public func fetchUsage() async throws -> ProviderUsage {
        // Fetch data from local credentials, config, or API
        let shortReset = Date().addingTimeInterval(3600 * 2.0)
        let weeklyReset = Date().addingTimeInterval(86400 * 4.0)
        
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 12.0,
            resetDate: shortReset
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly · all models",
            windowDurationHours: 168.0,
            usedPercent: 35.0,
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

3. Register your provider in [`UsageManager.swift`](Sources/AgentUsageLimits/Services/UsageManager.swift):
```swift
self.providers = [
    AntigravityUsageProvider(),
    ClaudeUsageProvider(),
    CodexUsageProvider(),
    YourProviderUsageProvider() // <-- Add here
]
```

4. (Optional) If you have a custom brand logo, add its vector shape in [`BrandIcons.swift`](Sources/AgentUsageLimits/Views/BrandIcons.swift).

---

## 🎨 UI Guidelines

- **Keep it minimal**: Follow native macOS aesthetics with clean typography and subtle progress bars.
- **Color usage**: Avoid heavy colored backgrounds; use subtle accent colors (`Color.blue` for progress, status dots for quota health).
- **Responsive**: Ensure the horizontal menu bar stack remains compact so it fits comfortably in menu bars with limited space.

---

## 📦 Pull Request Guidelines

1. Ensure the code compiles cleanly with no warnings (`swift build`).
2. Verify bundling works (`make bundle`).
3. Write clear, descriptive commit messages following [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat: add DeepSeek usage provider`, `fix: handle offline state gracefully`).
4. Open a Pull Request against the `main` or `dev` branch with a summary of your changes.

---

## 📜 Code of Conduct

Please be respectful, constructive, and collaborative in all discussions and pull requests.
