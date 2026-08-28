import SwiftUI
import AppKit

@main
struct AgentUsageLimitsApp: App {
    @StateObject private var usageManager = UsageManager()
    
    var body: some Scene {
        MenuBarExtra {
            PopoverDetailView(usageManager: usageManager)
        } label: {
            MenuBarView(usageManager: usageManager)
        }
        .menuBarExtraStyle(.window)
    }
}
