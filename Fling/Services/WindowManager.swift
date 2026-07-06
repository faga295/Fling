import AppKit
import ApplicationServices

/// Manages window manipulation using the macOS Accessibility API.
class WindowManager {
    static let shared = WindowManager()

    private let screenManager = ScreenManager.shared

    /// Tracks the last layout action applied to each window (by pid + window hash).
    /// Used for cross-display moves to re-apply the same layout on the target screen.
    private var lastLayoutAction: [String: WindowAction] = [:]

    /// Performs the given window action on the supplied target window, or falls back
    /// to the frontmost app's focused window when no target is available.
    func perform(_ action: WindowAction, on targetWindow: FocusableWindow? = nil) {
        let window: AXUIElement
        let windowKey: String

        if let targetWindow {
            window = targetWindow.windowElement
            windowKey = "\(targetWindow.pid)"
        } else {
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                  let focusedWindow = getFocusedWindowElement(for: frontmostApp.processIdentifier) else {
                return
            }

            window = focusedWindow
            windowKey = "\(frontmostApp.processIdentifier)"
        }

        switch action {
        case .left:
            snapToHalf(window, position: .left)
            lastLayoutAction[windowKey] = .left
        case .right:
            snapToHalf(window, position: .right)
            lastLayoutAction[windowKey] = .right
        case .top:
            snapToHalf(window, position: .top)
            lastLayoutAction[windowKey] = .top
        case .bottom:
            snapToHalf(window, position: .bottom)
            lastLayoutAction[windowKey] = .bottom
        case .maximize:
            maximize(window)
            lastLayoutAction[windowKey] = .maximize
        case .moveLeft:
            moveToAdjacentDisplay(window, direction: .left, windowKey: windowKey)
        case .moveRight:
            moveToAdjacentDisplay(window, direction: .right, windowKey: windowKey)
        }
    }

    // MARK: - Private: AX Element Access

    private func getFocusedWindowElement(for pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success else { return nil }
        return (focusedWindow as! AXUIElement)
    }

    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        var position = frame.origin
        var size = frame.size

        // Step 1: Move window to target position first (so it's on the right screen)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }

        // Step 2: Resize window
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // Step 3: Set position again to fix any OS adjustment caused by resizing
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
    }

    // MARK: - Private: Coordinate Conversion

    /// Converts AX coordinates (origin top-left) to NSScreen coordinates (origin bottom-left).
    private func axFrameToScreenFrame(_ axFrame: CGRect) -> CGRect? {
        WindowCoordinateConverter.screenFrame(fromAXFrame: axFrame)
    }

    private func screenFrameToAXFrame(_ screenFrame: CGRect) -> CGRect? {
        WindowCoordinateConverter.axFrame(fromScreenFrame: screenFrame)
    }

    // MARK: - Private: Actions

    private enum HalfPosition {
        case left, right, top, bottom
    }

    private func snapToHalf(_ window: AXUIElement, position: HalfPosition) {
        guard let axFrame = getWindowFrame(window) else { return }
        guard let screenFrame = axFrameToScreenFrame(axFrame) else { return }
        guard let screen = screenManager.screen(for: screenFrame) else { return }

        let visibleFrame = screen.visibleFrame
        let targetScreenFrame: CGRect

        switch position {
        case .left:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .right:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x + visibleFrame.width / 2,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .top:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y + visibleFrame.height / 2,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        case .bottom:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        }

        guard let targetAXFrame = screenFrameToAXFrame(targetScreenFrame) else { return }
        setWindowFrame(window, frame: targetAXFrame)
    }

    /// Snap window to a specific layout on a given target screen.
    /// Directly sets the target frame, then re-applies size to force constraint refresh.
    private func snapToLayoutOnScreen(_ window: AXUIElement, layout: WindowAction, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let targetScreenFrame: CGRect

        switch layout {
        case .left:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .right:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x + visibleFrame.width / 2,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .top:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y + visibleFrame.height / 2,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        case .bottom:
            targetScreenFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        case .maximize:
            targetScreenFrame = visibleFrame
        default:
            targetScreenFrame = visibleFrame
        }

        guard let targetAXFrame = screenFrameToAXFrame(targetScreenFrame) else { return }

        // Set the frame directly to the target position
        setWindowFrame(window, frame: targetAXFrame)

        // Re-apply size after a minimal delay to force app to recalculate constraints
        // for the new screen (handles apps with per-screen max-width limits)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.setWindowFrame(window, frame: targetAXFrame)
        }
    }

    private func maximize(_ window: AXUIElement) {
        guard let axFrame = getWindowFrame(window) else { return }
        guard let screenFrame = axFrameToScreenFrame(axFrame) else { return }
        guard let screen = screenManager.screen(for: screenFrame) else { return }

        guard let targetAXFrame = screenFrameToAXFrame(screen.visibleFrame) else { return }
        setWindowFrame(window, frame: targetAXFrame)
    }

    private func moveToAdjacentDisplay(_ window: AXUIElement, direction: HalfPosition, windowKey: String) {
        guard let axFrame = getWindowFrame(window) else { return }
        guard let screenFrame = axFrameToScreenFrame(axFrame) else { return }
        guard let currentScreen = screenManager.screen(for: screenFrame) else { return }

        let targetScreen: NSScreen?
        switch direction {
        case .left:
            targetScreen = screenManager.screenToLeft(of: currentScreen)
        case .right:
            targetScreen = screenManager.screenToRight(of: currentScreen)
        default:
            return
        }

        guard let target = targetScreen else { return }

        print("[Fling] moveToAdjacentDisplay")
        print("  windowKey: \(windowKey)")
        print("  lastLayoutAction: \(String(describing: lastLayoutAction[windowKey]))")
        print("  currentScreen.visibleFrame: \(currentScreen.visibleFrame)")
        print("  targetScreen.visibleFrame: \(target.visibleFrame)")

        // If we have a recorded layout action, re-apply it on the target screen.
        if let lastAction = lastLayoutAction[windowKey] {
            print("  → Re-applying saved layout: \(lastAction)")
            snapToLayoutOnScreen(window, layout: lastAction, screen: target)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let finalAX = self?.getWindowFrame(window) {
                    print("  finalAXFrame: \(finalAX)")
                }
            }
            return
        }

        // No saved action — try to detect the layout from coordinates
        let detectedLayout = screenManager.detectLayout(windowFrame: screenFrame, on: currentScreen)
        print("  → No saved layout, detected: \(detectedLayout)")

        if detectedLayout != .custom {
            // Map detected layout to a WindowAction for snapToLayoutOnScreen
            let actionForLayout: WindowAction
            switch detectedLayout {
            case .maximized: actionForLayout = .maximize
            case .leftHalf: actionForLayout = .left
            case .rightHalf: actionForLayout = .right
            case .topHalf: actionForLayout = .top
            case .bottomHalf: actionForLayout = .bottom
            case .custom: actionForLayout = .maximize // won't reach here
            }
            snapToLayoutOnScreen(window, layout: actionForLayout, screen: target)
            // Also save it for next time
            lastLayoutAction[windowKey] = actionForLayout
        } else {
            // True custom layout — use ratio fallback
            let newScreenFrame = screenManager.targetFrame(for: screenFrame, from: currentScreen, to: target)
            guard let newAXFrame = screenFrameToAXFrame(newScreenFrame) else { return }
            setWindowFrame(window, frame: newAXFrame)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let finalAX = self?.getWindowFrame(window) {
                print("  finalAXFrame: \(finalAX)")
            }
        }
    }
}
