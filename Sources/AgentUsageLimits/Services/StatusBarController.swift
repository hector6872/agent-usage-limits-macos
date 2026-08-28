import SwiftUI
import AppKit
import Combine

/// Borderless, clean floating panel without the popover top triangle arrow
final class MenuBarPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.contentViewController = contentViewController
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

/// Native AppKit Status Bar Controller using ImageRenderer and clean floating panel without popover arrow
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var usageManager: UsageManager
    private var cancellables = Set<AnyCancellable>()
    private var panel: MenuBarPanel?
    private var eventMonitor: Any?
    
    public init(usageManager: UsageManager) {
        self.usageManager = usageManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        super.init()
        
        setupStatusButton()
        observeUsageChanges()
        observeThemeChanges()
        renderStatusImage()
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
        if let panel = panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }
    
    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        
        let hostingController = NSHostingController(
            rootView: PopoverDetailView(usageManager: usageManager)
        )
        let panel = MenuBarPanel(contentViewController: hostingController)
        self.panel = panel
        
        let targetSize = hostingController.view.fittingSize
        let buttonScreenRect = buttonWindow.convertToScreen(button.bounds)
        
        // Position panel right beneath the status item button
        let x = buttonScreenRect.midX - (targetSize.width / 2.0)
        let y = buttonScreenRect.minY - targetSize.height - 4.0
        
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
        let clampedX = min(max(screenFrame.minX + 8, x), screenFrame.maxX - targetSize.width - 8)
        
        panel.setFrame(NSRect(x: clampedX, y: y, width: targetSize.width, height: targetSize.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 1.0
        }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanel()
        }
    }
    
    private func closePanel() {
        guard let panel = panel, panel.isVisible else { return }
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                panel.orderOut(nil)
                self?.panel = nil
            }
        })
    }
}
