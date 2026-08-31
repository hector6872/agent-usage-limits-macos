import SwiftUI
import AppKit

/// Detail popover window matching the clean, minimal aesthetic with live updating timestamp and inline refresh badge
public struct PopoverDetailView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @State private var showingSettings: Bool = false
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Providers list
            let active = usageManager.activeUsages
            if active.isEmpty {
                emptyStateView
            } else {
                ForEach(active) { usage in
                    ProviderSectionView(usage: usage)
                    
                    if usage.id != active.last?.id {
                        Divider()
                            .padding(.vertical, 12)
                    }
                }
            }
            
            if showingSettings {
                Divider()
                    .padding(.vertical, 12)
                settingsView
            }
            
            Divider()
                .padding(.top, 14)
                .padding(.bottom, 10)
            
            // Bottom Action Footer with live ticking badge
            footerView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(l10n["no_active_providers"])
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Button(l10n["enable_providers_in_settings"]) {
                withAnimation { showingSettings = true }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Settings View
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n["providers_header"])
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.secondary)
            
            ForEach(usageManager.providers, id: \.id) { provider in
                HStack {
                    BrandIconView(symbol: provider.iconSymbol, size: 12)
                    Text(provider.displayName)
                        .font(.system(size: 12.5))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { provider.isEnabled },
                        set: { _ in usageManager.toggleProvider(id: provider.id) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            
            Divider().padding(.vertical, 2)
            
            // Launch at login toggle
            HStack {
                Text(l10n["launch_at_login"])
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.top, 2)
            
            // Language selector
            HStack {
                Text(l10n["language_label"])
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $l10n.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.localizedName(with: l10n)).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 130)
            }
            .padding(.top, 2)
            
            // Refresh interval (1m, 3m default, 5m, 15m, 30m)
            HStack {
                Text(l10n["refresh_interval"])
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $usageManager.refreshIntervalSeconds) {
                    Text("1m").tag(60.0)
                    Text("3m").tag(180.0)
                    Text("5m").tag(300.0)
                    Text("15m").tag(900.0)
                    Text("30m").tag(1800.0)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 80)
            }
            .padding(.top, 2)
            
            Button(l10n["help"]) {
                if let url = URL(string: "https://github.com/hector6872/agent-usage-limits-macos") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.top, 4)
            
            Button(l10n["quit_app"]) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.red.opacity(0.85))
            .padding(.top, 2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer()
            
            // Only render and tick the live badge if there is at least one active provider
            if !usageManager.activeUsages.isEmpty {
                LiveRefreshBadgeView(usageManager: usageManager, l10n: l10n)
            }
            
            // Settings button on the far right
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSettings.toggle()
                }
            } label: {
                Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n["providers_header"])
        }
    }
}

/// Live ticking badge view updating every second
struct LiveRefreshBadgeView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var l10n: LocalizationManager
    
    var body: some View {
        TimelineView(.periodic(from: Date.now, by: 1.0)) { context in
            BadgeContent(date: context.date, usageManager: usageManager, l10n: l10n)
        }
    }
}

/// Content inside the pill badge
struct BadgeContent: View {
    let date: Date
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var l10n: LocalizationManager
    
    var body: some View {
        let canRefresh = usageManager.canManualRefresh(at: date)
        let cooldown = usageManager.cooldownRemainingSeconds(at: date)
        
        HStack(spacing: 6) {
            // Time text (updates every second)
            Text(l10n.timeAgo(since: usageManager.lastRefreshedDate))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(.primary.opacity(0.8))
            
            // Refresh icon inside badge
            Button {
                if canRefresh {
                    Task {
                        await usageManager.refreshAll()
                    }
                }
            } label: {
                if usageManager.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(canRefresh ? .primary.opacity(0.85) : .secondary.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .help(tooltipText(cooldown: cooldown))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
        )
    }
    
    private func tooltipText(cooldown: Int) -> String {
        if usageManager.refreshIntervalSeconds <= 60.0 {
            return l10n["auto_refresh_1m_hint"]
        }
        if cooldown > 0 {
            return l10n.string("cooldown_hint", cooldown)
        }
        return l10n["refresh_now_hint"]
    }
}

/// Minimalist provider usage section
struct ProviderSectionView: View {
    let usage: ProviderUsage
    @ObservedObject private var l10n = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header: "YOUR USAGE LIMITS · PROVIDER" / "TUS LÍMITES DE USO · PROVIDER"
            HStack(spacing: 5) {
                Text(l10n.string("usage_limits_header", usage.displayName.uppercased()))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.85))
                    .tracking(0.3)
                
                Spacer()
                
                BrandIconView(symbol: usage.iconSymbol, size: 11)
                    .opacity(0.6)
            }
            
            // 5-Hour / Short limit row
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(usage.shortWindow.localizedTitle)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if usage.isActive {
                        let remaining = usage.shortWindow.roundedRemainingPercent
                        Text("\(remaining)% · \(usage.shortWindow.localizedResetsFormatted)")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.primary.opacity(0.85))
                    } else {
                        Text(l10n["not_active"])
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                // Thin progress bar matching menu badge health color
                MinimalProgressBar(
                    percent: usage.isActive ? usage.shortWindow.remainingPercent : 0,
                    fillColor: usage.isActive ? usage.shortWindow.healthStatus.color : Color.gray.opacity(0.3)
                )
            }
            
            // Weekly limit row
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(usage.weeklyWindow.localizedTitle)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if usage.isActive {
                        let remaining = usage.weeklyWindow.roundedRemainingPercent
                        Text("\(remaining)% · \(usage.weeklyWindow.localizedResetsFormatted)")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.primary.opacity(0.85))
                    } else {
                        Text(l10n["not_active"])
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                // Thin progress bar matching menu badge health color
                MinimalProgressBar(
                    percent: usage.isActive ? usage.weeklyWindow.remainingPercent : 0,
                    fillColor: usage.isActive ? usage.weeklyWindow.healthStatus.color : Color.gray.opacity(0.3)
                )
            }
        }
    }
}

/// Thin, subtle progress bar matching the reference image
struct MinimalProgressBar: View {
    let percent: Double
    let fillColor: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                    .frame(height: 3.5)
                
                // Filled portion
                let clampedPercent = max(0.0, min(100.0, percent))
                let fillWidth = max(3.5, geo.size.width * CGFloat(clampedPercent / 100.0))
                
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth, height: 3.5)
            }
        }
        .frame(height: 3.5)
    }
}
