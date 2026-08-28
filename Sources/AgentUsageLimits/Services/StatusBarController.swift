import SwiftUI
import AppKit
import Combine

/// Custom transparent overlay that intercepts clicks to prevent NSStatusBarButton from drawing rectangular box highlights
final class StatusItemOverlayView: NSView {
    var onClick: (() -> Void)?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Zero custom or default highlight drawing
    }
}

/// Borderless, clean floating panel without titlebar and without popover top triangle arrow
final class MenuBarPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

/// Custom hosting controller that dynamically reports content size changes when settings expand/collapse
final class AutoSizingHostingController: NSHostingController<PopoverDetailView> {
    var onSizeChanged: ((CGSize) -> Void)?
    
    override func viewDidLayout() {
        super.viewDidLayout()
        let fittingSize = view.fittingSize
        if fittingSize.height > 0 {
            onSizeChanged?(fittingSize)
        }
    }
}

/// Native AppKit Status Bar Controller using ImageRenderer and clean auto-sizing floating panel
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var usageManager: UsageManager
    private var cancellables = Set<AnyCancellable>()
    private var panel: MenuBarPanel?
    private var hostingController: AutoSizingHostingController?
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
        
        button.isBordered = false
        button.wantsLayer = true
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsBorderOnlyWhileMouseInside = false
        }
        
        button.subviews.forEach { $0.removeFromSuperview() }
        
        let overlay = StatusItemOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onClick = { [weak self] in
            self?.togglePopover()
        }
        
        button.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: button.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
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
    
    public func togglePopover() {
        if let panel = panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }
    
    private func showPanel() {
        guard let button = statusItem.button, button.window != nil else { return }
        
        let hosting = AutoSizingHostingController(
            rootView: PopoverDetailView(usageManager: usageManager)
        )
        self.hostingController = hosting
        
        let panel = MenuBarPanel(contentViewController: hosting)
        self.panel = panel
        
        hosting.onSizeChanged = { [weak self] size in
            Task { @MainActor [weak self] in
                self?.updatePanelFrame(for: size)
            }
        }
        
        let initialSize = hosting.view.fittingSize
        updatePanelFrame(for: initialSize)
        
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
    
    private func updatePanelFrame(for size: CGSize) {
        guard let panel = panel, let button = statusItem.button, let buttonWindow = button.window else { return }
        guard size.height > 0 else { return }
        
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 330
        let height: CGFloat = size.height
        
        // Exact bottom edge of the macOS menu bar on this screen
        let menuBarBottomY = screen.visibleFrame.maxY
        let y = menuBarBottomY - height - 4.0 // Exactly 4pt below menu bar
        
        let buttonRectOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = buttonRectOnScreen.midX - (width / 2.0)
        let clampedX = min(max(screen.visibleFrame.minX + 8, x), screen.visibleFrame.maxX - width - 8)
        
        let targetFrame = NSRect(x: clampedX, y: y, width: width, height: height)
        
        if panel.frame.size != targetFrame.size || panel.frame.origin != targetFrame.origin {
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    panel.animator().setFrame(targetFrame, display: true)
                }
            } else {
                panel.setFrame(targetFrame, display: true)
            }
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
                self?.hostingController = nil
            }
        })
    }
}
