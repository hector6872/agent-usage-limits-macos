import SwiftUI
import AppKit

@main
struct AgentUsageLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Custom Application Delegate hosting the native NSStatusItem and popover
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var usageManager: UsageManager?
    private var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = UsageManager()
        self.usageManager = manager
        self.statusBarController = StatusBarController(usageManager: manager)
    }
}
