import SwiftUI
import AppKit

/// Detail popover window matching the clean, minimal aesthetic with multi-language support
public struct PopoverDetailView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject private var l10n = LocalizationManager.shared
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
            
            // Bottom Action Footer: "Refresh" + "Updated just now" + subtle settings/quit
            footerView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 330)
        .background(Color(NSColor.windowBackgroundColor))
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
            
            // Language selector
            HStack {
                Text(l10n["language_label"])
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $l10n.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 130)
            }
            
            // Refresh interval
            HStack {
                Text(l10n["refresh_interval"])
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $usageManager.refreshIntervalSeconds) {
                    Text("30s").tag(30.0)
                    Text("1m").tag(60.0)
                    Text("5m").tag(300.0)
                    Text("15m").tag(900.0)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 80)
            }
            .padding(.top, 2)
            
            Button(l10n["quit_app"]) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.red.opacity(0.85))
            .padding(.top, 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(alignment: .center) {
            // Refresh text button
            Button {
                Task {
                    await usageManager.refreshAll()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(l10n["refresh"])
                        .font(.system(size: 13, weight: .regular))
                    if usageManager.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(usageManager.isRefreshing)
            
            Spacer()
            
            // Subtle Settings gear
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSettings.toggle()
                }
            } label: {
                Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            
            // Native time ago pill tag
            Text(l10n.timeAgo(since: usageManager.lastRefreshedDate))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(.primary.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                )
        }
    }
}

/// Minimalist provider usage section
struct ProviderSectionView: View {
    let usage: ProviderUsage
    @ObservedObject private var l10n = LocalizationManager.shared
    
    private let barBlue = Color(red: 0.12, green: 0.42, blue: 0.90) // Native clean blue accent
    
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
                    
                    Text("\(Int(usage.shortWindow.usedPercent))% · \(usage.shortWindow.localizedResetsFormatted)")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.primary.opacity(0.85))
                }
                
                // Thin progress bar
                MinimalProgressBar(
                    percent: usage.shortWindow.usedPercent,
                    fillColor: barBlue
                )
            }
            
            // Weekly limit row
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(usage.weeklyWindow.localizedTitle)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(Int(usage.weeklyWindow.usedPercent))% · \(usage.weeklyWindow.localizedResetsFormatted)")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.primary.opacity(0.85))
                }
                
                // Thin progress bar
                MinimalProgressBar(
                    percent: usage.weeklyWindow.usedPercent,
                    fillColor: barBlue
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
