import SwiftUI
import AppKit
import Combine

/// Native AppKit Status Bar Controller that hosts custom SwiftUI views with full layout fidelity in macOS Sonoma & Sequoia
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var usageManager: UsageManager
    private var cancellables = Set<AnyCancellable>()
    private var hostingView: NSHostingView<MenuBarView>?
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
        
        // Create variable-length status item in system menu bar
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        
        super.init()
        
        setupPopover()
        setupStatusButton()
        observeUsageChanges()
    }
    
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverDetailView(usageManager: usageManager)
        )
    }
    
    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        let menuBarView = MenuBarView(usageManager: usageManager)
        let hosting = NSHostingView(rootView: menuBarView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hosting)
        
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        
        self.hostingView = hosting
        updateButtonFrame()
    }
    
    private func observeUsageChanges() {
        usageManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Allow SwiftUI to calculate the new intrinsic content size, then update button
                DispatchQueue.main.async {
                    self?.updateButtonFrame()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateButtonFrame() {
        guard let button = statusItem.button, let hosting = hostingView else { return }
        let targetSize = hosting.fittingSize
        if targetSize.width > 0 {
            statusItem.length = max(24, targetSize.width)
            button.frame = NSRect(x: 0, y: 0, width: statusItem.length, height: targetSize.height)
        }
    }
    
    @objc public func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Update popover view controller with fresh state
            popover.contentViewController = NSHostingController(
                rootView: PopoverDetailView(usageManager: usageManager)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
