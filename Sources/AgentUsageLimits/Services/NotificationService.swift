import Foundation
import UserNotifications

/// Service for managing macOS user notifications when quota windows enter critical health status (< 25% remaining)
@MainActor
public final class NotificationService {
    public static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private var notifiedWindows: Set<String> = []
    
    private init() {}
    
    /// Requests notification permissions from the user
    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    /// Checks current usages and sends a notification for each window entering critical level (< 25% remaining)
    public func checkAndNotifyCriticalQuotas(usages: [String: ProviderUsage]) {
        let l10n = LocalizationManager.shared
        
        for (_, usage) in usages {
            guard usage.isActive else {
                // If provider is inactive, clear any past notified flags
                notifiedWindows.remove("\(usage.providerId)_short")
                notifiedWindows.remove("\(usage.providerId)_weekly")
                continue
            }
            
            // 1. Check Short window (e.g. 5-hour limit)
            let shortKey = "\(usage.providerId)_short"
            if usage.shortWindow.healthStatus == .critical {
                if !notifiedWindows.contains(shortKey) {
                    notifiedWindows.insert(shortKey)
                    sendNotification(
                        title: l10n.string("critical_notification_title", usage.displayName),
                        body: l10n.string(
                            "critical_notification_body",
                            usage.shortWindow.localizedTitle,
                            "\(usage.shortWindow.roundedRemainingPercent)",
                            usage.shortWindow.localizedResetsFormatted
                        ),
                        identifier: shortKey
                    )
                }
            } else {
                // Recovered from critical or reset
                notifiedWindows.remove(shortKey)
            }
            
            // 2. Check Weekly window
            let weeklyKey = "\(usage.providerId)_weekly"
            if usage.weeklyWindow.healthStatus == .critical {
                if !notifiedWindows.contains(weeklyKey) {
                    notifiedWindows.insert(weeklyKey)
                    sendNotification(
                        title: l10n.string("critical_notification_title", usage.displayName),
                        body: l10n.string(
                            "critical_notification_body",
                            usage.weeklyWindow.localizedTitle,
                            "\(usage.weeklyWindow.roundedRemainingPercent)",
                            usage.weeklyWindow.localizedResetsFormatted
                        ),
                        identifier: weeklyKey
                    )
                }
            } else {
                // Recovered from critical or reset
                notifiedWindows.remove(weeklyKey)
            }
        }
    }
    
    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "\(identifier)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        center.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
}
