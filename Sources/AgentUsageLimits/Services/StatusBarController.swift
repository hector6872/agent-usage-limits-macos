import SwiftUI
import AppKit
import Combine

/// Native AppKit Status Bar Controller using ImageRenderer to produce native NSStatusBarButton images
/// Automatically adapts to Light and Dark system themes in real-time
@MainActor
public final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var usageManager: UsageManager
    private var cancellables = Set<AnyCancellable>()
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        
        super.init()
        
        setupPopover()
        setupStatusButton()
        observeUsageChanges()
        observeThemeChanges()
        renderStatusImage()
    }
    
    private func setupPopover() {
        popover.delegate = self
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
        button.subviews.forEach { $0.removeFromSuperview() }
    }
    
    private func observeUsageChanges() {
        usageManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.renderStatusImage()
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeThemeChanges() {
        // Listen to system theme changes (Light Mode <-> Dark Mode)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.renderStatusImage()
            }
        }
        
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusImage()
            }
            .store(in: &cancellables)
    }
    
    private var isCurrentDarkMode: Bool {
        if let button = statusItem.button {
            return button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    public func renderStatusImage() {
        guard let button = statusItem.button else { return }
        
        let isDark = isCurrentDarkMode
        let view = MenuBarView(usageManager: usageManager, isDarkMode: isDark)
            .environment(\.colorScheme, isDark ? .dark : .light)
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        
        if let image = renderer.nsImage {
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        }
    }
    
    @objc public func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(
                rootView: PopoverDetailView(usageManager: usageManager)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
