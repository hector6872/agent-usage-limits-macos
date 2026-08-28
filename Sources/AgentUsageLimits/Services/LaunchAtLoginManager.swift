import Foundation
import ServiceManagement
import SwiftUI
import Combine

/// Manager responsible for registering/unregistering the app to launch on system login using SMAppService
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public var isEnabled: Bool = false
    
    public init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    /// Toggles or sets launch at login state
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            self.isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to update Launch at Login status: \(error.localizedDescription)")
            self.isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
