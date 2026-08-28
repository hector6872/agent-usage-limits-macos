import Foundation
import SwiftUI
import Combine

/// Central manager that coordinates all quota providers and manages periodic polling.
@MainActor
public final class UsageManager: ObservableObject {
    @Published public private(set) var usages: [String: ProviderUsage] = [:]
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var lastRefreshedDate: Date = Date()
    @Published public var refreshIntervalSeconds: TimeInterval = 60.0 {
        didSet {
            setupTimer()
        }
    }
    
    /// Registered providers
    public private(set) var providers: [any UsageProvider] = []
    
    private var timerTask: Task<Void, Never>?
    
    public init(providers: [any UsageProvider] = []) {
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
    
    /// Registers a new provider plugin dynamically
    public func register(provider: any UsageProvider) {
        if !providers.contains(where: { $0.id == provider.id }) {
            providers.append(provider)
            Task {
                await refreshProvider(provider)
            }
        }
    }
    
    /// Toggles whether a provider is enabled
    public func toggleProvider(id: String) {
        if let index = providers.firstIndex(where: { $0.id == id }) {
            providers[index].isEnabled.toggle()
            objectWillChange.send()
        }
    }
    
    /// Refreshes all enabled providers concurrently
    public func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { 
            isRefreshing = false 
            lastRefreshedDate = Date()
        }
        
        await withTaskGroup(of: (String, ProviderUsage?).self) { group in
            for provider in providers where provider.isEnabled {
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
                            weeklyWindow: QuotaWindow(name: "Weekly · all models", usedPercent: 0),
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
                weeklyWindow: QuotaWindow(name: "Weekly · all models", usedPercent: 0),
                errorMessage: error.localizedDescription
            )
        }
    }
    
    private func setupTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshIntervalSeconds ?? 60.0))
                if Task.isCancelled { break }
                await self?.refreshAll()
            }
        }
    }
}
