import AppKit
import SwiftUI

// MARK: - Custom Floating Panel

/// A floating panel that can become key window to receive keyboard events.
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// MARK: - Panel Controller

/// Controls the floating panel window and key event handling.
class PanelController {
    private var panel: FloatingPanel?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var mouseMonitor: Any?
    private var panelViewModel = PanelViewModel()

    /// Border overlay for the focused window.
    private var borderOverlay = BorderOverlayWindow()

    /// Timer that continuously tracks the focused window position for the border.
    private var borderTrackingTimer: Timer?

    /// Window cycling state.
    private var visibleWindows: [FocusableWindow] = []
    private var currentWindowIndex: Int = 0
    private var targetWindow: FocusableWindow?

    /// When true, ignore dismiss triggers (mouse clicks) because we're executing an action.
    private var isPerformingAction = false

    var onAction: ((WindowAction, FocusableWindow?) -> Void)?
    var onDismiss: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        let initialTargetWindow = WindowCycler.shared.getFocusedWindow()
        targetWindow = initialTargetWindow

        // Get the screen where the currently focused window is
        let screen = getCurrentScreen(for: initialTargetWindow)

        panelViewModel.highlightedAction = nil

        let panelView = PanelView(viewModel: panelViewModel)

        let hostingView = NSHostingView(rootView: panelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 260)

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 260))
        panel.contentView = hostingView

        // Center on the current screen
        if let screen = screen {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Show border around currently focused window
        updateBorderOverlay()

        // Start a timer that continuously tracks the focused window for border updates
        borderTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateBorderOverlay()
        }

        // Cache visible windows for J/K cycling
        visibleWindows = WindowCycler.shared.getVisibleWindows()
        updateCurrentWindowIndex()

        // Install local key event monitor (when Fling is the active app)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyEvent(event) {
                return nil // Consume the event
            }
            return event
        }

        // Install global key event monitor (when another app is active)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Monitor for mouse clicks anywhere to dismiss panel
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }
            if !self.isPerformingAction {
                self.dismiss()
            }
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers else { return false }
        let modifiers = event.modifierFlags

        // Vim-style dismiss: Ctrl+C, Ctrl+[
        if modifiers.contains(.control) && (chars == "c" || chars == "[") {
            dismiss()
            return true
        }

        // Ignore keys with Cmd or Ctrl modifiers
        if modifiers.contains(.command) || modifiers.contains(.control) {
            return false
        }

        // Tab: cycle to next window
        if event.keyCode == 48 && !modifiers.contains(.shift) {
            cycleWindow(forward: true)
            return true
        }

        // J/K with Shift: cycle windows
        if modifiers.contains(.shift) {
            switch chars.lowercased() {
            case "j":
                cycleWindow(forward: true)
                return true
            case "k":
                cycleWindow(forward: false)
                return true
            default:
                break
            }
        }

        let action: WindowAction?

        switch chars.lowercased() {
        case "h":
            action = modifiers.contains(.shift) ? .moveLeft : .left
        case "l":
            action = modifiers.contains(.shift) ? .moveRight : .right
        case "k":
            action = .top
        case "j":
            action = .bottom
        case " ":
            action = .maximize
        case "q":
            dismiss()
            return true
        default:
            if chars == "\u{1b}" { // Escape
                dismiss()
                return true
            }
            return false
        }

        if let action = action {
            // Set guard flag to prevent mouse events from dismissing during action
            isPerformingAction = true

            // Highlight the cell briefly, execute action, keep panel open
            panelViewModel.highlightedAction = action

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.onAction?(action, self.targetWindow)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.panelViewModel.highlightedAction = nil
                    self.isPerformingAction = false
                }
            }
            return true
        }

        return false
    }

    // MARK: - Window Cycling

    private func cycleWindow(forward: Bool) {
        let direction = forward ? "forward" : "backward"
        guard !visibleWindows.isEmpty else {
            print("[Fling] cycleWindow direction=\(direction) skipped cachedCount=0")
            return
        }

        print("[Fling] cycleWindow direction=\(direction) currentIndex=\(currentWindowIndex) cachedCount=\(visibleWindows.count)")

        if let nextIndex = nextUsableWindowIndex(forward: forward, source: "cache") {
            focusWindow(at: nextIndex)
            return
        }

        print("[Fling] cycleWindow no usable cached candidate; refreshing window list")
        visibleWindows = WindowCycler.shared.getVisibleWindows()
        updateCurrentWindowIndex()
        print("[Fling] cycleWindow refreshedCount=\(visibleWindows.count) currentIndex=\(currentWindowIndex)")

        if let nextIndex = nextUsableWindowIndex(forward: forward, source: "refresh") {
            focusWindow(at: nextIndex)
        } else {
            print("[Fling] cycleWindow no usable candidate after refresh")
        }
    }

    private func nextUsableWindowIndex(forward: Bool, source: String) -> Int? {
        guard !visibleWindows.isEmpty else { return nil }

        var index = currentWindowIndex
        for _ in 0..<visibleWindows.count {
            if forward {
                index = (index + 1) % visibleWindows.count
            } else {
                index = (index - 1 + visibleWindows.count) % visibleWindows.count
            }

            let report = WindowCycler.shared.debugUsabilityReport(for: visibleWindows[index])
            print("[Fling] cycleWindow candidate source=\(source) index=\(index) \(report.description)")

            if report.isUsable {
                return index
            }
        }

        return nil
    }

    private func focusWindow(at index: Int) {
        currentWindowIndex = index
        let targetWindow = visibleWindows[currentWindowIndex]
        self.targetWindow = targetWindow
        let report = WindowCycler.shared.debugUsabilityReport(for: targetWindow)
        print("[Fling] cycleWindow focus index=\(index) \(report.description)")
        WindowCycler.shared.focus(targetWindow)

        // Update border to new focused window after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if let frame = WindowCycler.shared.usableFrame(of: targetWindow.windowElement, appName: targetWindow.appName) {
                print("[Fling] cycleWindow overlay app=\"\(targetWindow.appName)\" pid=\(targetWindow.pid) frame=\(NSStringFromRect(frame))")
                self.borderOverlay.updateFrame(axFrame: frame)
            } else {
                let report = WindowCycler.shared.debugUsabilityReport(for: targetWindow)
                print("[Fling] cycleWindow overlay hidden \(report.description)")
                self.borderOverlay.hide()
            }
        }
    }

    private func updateCurrentWindowIndex() {
        guard let focusedFrame = targetWindow?.frame ?? WindowCycler.shared.getFocusedWindowFrame() else { return }

        // Find the index of the currently focused window
        for (index, win) in visibleWindows.enumerated() {
            if abs(win.frame.origin.x - focusedFrame.origin.x) < 10 &&
               abs(win.frame.origin.y - focusedFrame.origin.y) < 10 {
                currentWindowIndex = index
                break
            }
        }
    }

    // MARK: - Border Overlay

    private func updateBorderOverlay() {
        guard let targetWindow else {
            borderOverlay.hide()
            return
        }

        if let frame = WindowCycler.shared.usableFrame(of: targetWindow.windowElement, appName: targetWindow.appName) {
            borderOverlay.updateFrame(axFrame: frame)
        } else {
            borderOverlay.hide()
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        borderTrackingTimer?.invalidate()
        borderTrackingTimer = nil

        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let mouseMonitor = mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        borderOverlay.hide()
        targetWindow = nil
        panel?.orderOut(nil)
        panel = nil
        onDismiss?()
    }

    // MARK: - Helpers

    private func getCurrentScreen(for targetWindow: FocusableWindow?) -> NSScreen? {
        guard let axFrame = targetWindow?.frame,
              let screenFrame = WindowCoordinateConverter.screenFrame(fromAXFrame: axFrame) else {
            return NSScreen.main
        }

        return ScreenManager.shared.screen(for: screenFrame) ?? NSScreen.main
    }
}
