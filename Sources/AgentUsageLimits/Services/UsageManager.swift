import Foundation
import SwiftUI
import Combine

/// Central manager that coordinates all quota providers, manages periodic polling, and persists preferences.
@MainActor
public final class UsageManager: ObservableObject {
    @Published public private(set) var usages: [String: ProviderUsage] = [:]
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var lastRefreshedDate: Date = Date()
    
    /// Auto-refresh interval persisted in UserDefaults (default 3 minutes = 180 seconds)
    @Published public var refreshIntervalSeconds: TimeInterval = 180.0 {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: "refresh_interval_seconds")
            setupTimer()
        }
    }
    
    /// Registered providers
    public private(set) var providers: [any UsageProvider] = []
    
    private var timerTask: Task<Void, Never>?
    
    public init(providers: [any UsageProvider] = []) {
        // Load saved refresh interval
        let savedInterval = UserDefaults.standard.double(forKey: "refresh_interval_seconds")
        if savedInterval > 0 {
            self.refreshIntervalSeconds = savedInterval
        }
        
        if providers.isEmpty {
            // Default built-in providers: Antigravity, Claude, Codex
            self.providers = [
                AntigravityUsageProvider(),
                ClaudeUsageProvider(),
                CodexUsageProvider()
            ]
        } else {
            self.providers = providers
        }
        
        // Restore saved isEnabled preferences for each provider
        for i in 0..<self.providers.count {
            let key = "provider_\(self.providers[i].id)_enabled"
            if UserDefaults.standard.object(forKey: key) != nil {
                self.providers[i].isEnabled = UserDefaults.standard.bool(forKey: key)
            }
        }
        
        setupTimer()
        Task {
            await refreshAll()
        }
    }
    
    deinit {
        timerTask?.cancel()
    }
    
    /// Returns the usages of all currently enabled providers in registration order
    public var activeUsages: [ProviderUsage] {
        providers.compactMap { provider in
            guard provider.isEnabled else { return nil }
            return usages[provider.id]
        }
    }
    
    /// Whether manual refresh button is allowed to be pressed at the given time
    public func canManualRefresh(at date: Date = Date()) -> Bool {
        guard !isRefreshing else { return false }
        // If auto-refresh is 1 minute (<= 60s), manual refresh is disabled
        guard refreshIntervalSeconds > 60.0 else { return false }
        // 1-minute cooldown from last refresh
        let elapsed = date.timeIntervalSince(lastRefreshedDate)
        return elapsed >= 60.0
    }
    
    /// Cooldown remaining in seconds (0 if ready)
    public func cooldownRemainingSeconds(at date: Date = Date()) -> Int {
        guard refreshIntervalSeconds > 60.0 else { return 0 }
        let elapsed = date.timeIntervalSince(lastRefreshedDate)
        return max(0, 60 - Int(elapsed))
    }
    
    /// Registers a new provider plugin dynamically
    public func register(provider: any UsageProvider) {
        if !providers.contains(where: { $0.id == provider.id }) {
            var newProvider = provider
            let key = "provider_\(newProvider.id)_enabled"
            if UserDefaults.standard.object(forKey: key) != nil {
                newProvider.isEnabled = UserDefaults.standard.bool(forKey: key)
            }
            providers.append(newProvider)
            Task {
                await refreshProvider(newProvider)
            }
        }
    }
    
    /// Toggles whether a provider is enabled and saves preference
    public func toggleProvider(id: String) {
        if let index = providers.firstIndex(where: { $0.id == id }) {
            providers[index].isEnabled.toggle()
            UserDefaults.standard.set(providers[index].isEnabled, forKey: "provider_\(id)_enabled")
            objectWillChange.send()
            if providers[index].isEnabled {
                Task {
                    await refreshProvider(providers[index])
                }
            }
        }
    }
    
    /// Refreshes all enabled providers concurrently
    public func refreshAll() async {
        guard !isRefreshing else { return }
        let enabledProviders = providers.filter { $0.isEnabled }
        guard !enabledProviders.isEmpty else { return }
        
        isRefreshing = true
        defer { 
            isRefreshing = false 
            lastRefreshedDate = Date()
        }
        
        await withTaskGroup(of: (String, ProviderUsage?).self) { group in
            for provider in enabledProviders {
                group.addTask {
                    do {
                        let usage = try await provider.fetchUsage()
                        return (provider.id, usage)
                    } catch {
                        let fallbackUsage = ProviderUsage(
                            providerId: provider.id,
                            displayName: provider.displayName,
                            iconSymbol: provider.iconSymbol,
                            shortWindow: QuotaWindow(name: "5-hour limit", usedPercent: 0),
                            weeklyWindow: QuotaWindow(name: "Weekly", usedPercent: 0),
                            errorMessage: error.localizedDescription
                        )
                        return (provider.id, fallbackUsage)
                    }
                }
            }
            
            for await (providerId, usage) in group {
                if let usage = usage {
                    self.usages[providerId] = usage
                }
            }
        }
    }
    
    private func refreshProvider(_ provider: any UsageProvider) async {
        do {
            let usage = try await provider.fetchUsage()
            self.usages[provider.id] = usage
        } catch {
            self.usages[provider.id] = ProviderUsage(
                providerId: provider.id,
                displayName: provider.displayName,
                iconSymbol: provider.iconSymbol,
                shortWindow: QuotaWindow(name: "5-hour limit", usedPercent: 0),
                weeklyWindow: QuotaWindow(name: "Weekly", usedPercent: 0),
                errorMessage: error.localizedDescription
            )
        }
    }
    
    private func setupTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshIntervalSeconds ?? 180.0))
                if Task.isCancelled { break }
                await self?.refreshAll()
            }
        }
    }
}
