import AppKit
import ApplicationServices

/// Represents a window that can be focused.
struct FocusableWindow {
    let pid: pid_t
    let windowElement: AXUIElement
    let appName: String
    let frame: CGRect // AX coordinates
}

/// Manages listing and cycling through visible windows.
class WindowCycler {
    static let shared = WindowCycler()

    private let minimumWindowSize = CGSize(width: 100, height: 100)

    private struct WindowAXMetadata {
        let title: String?
        let role: String?
        let subrole: String?
    }

    private struct WindowUsabilityStatus {
        let isUsable: Bool
        let reason: String
        let axFrame: CGRect?
        let screenFrame: CGRect?
        let metadata: WindowAXMetadata
    }

    /// Returns all visible windows across all apps, sorted by position (top-left to bottom-right).
    func getVisibleWindows() -> [FocusableWindow] {
        var windows: [FocusableWindow] = []

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
        }

        for app in runningApps {
            let appName = app.localizedName ?? "Unknown"
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowList: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowList)

            guard result == .success, let axWindows = windowList as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                guard let frame = usableFrame(of: axWindow, appName: appName, minimumSize: minimumWindowSize) else { continue }

                let focusable = FocusableWindow(
                    pid: app.processIdentifier,
                    windowElement: axWindow,
                    appName: appName,
                    frame: frame
                )
                windows.append(focusable)
            }
        }

        // Sort by position: top to bottom, left to right
        windows.sort { a, b in
            if abs(a.frame.origin.y - b.frame.origin.y) < 50 {
                return a.frame.origin.x < b.frame.origin.x
            }
            return a.frame.origin.y < b.frame.origin.y
        }

        return windows
    }

    /// Returns true when a cached focusable window is still visible and suitable for cycling.
    func isUsable(_ window: FocusableWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              app.activationPolicy == .regular,
              !app.isHidden else {
            return false
        }

        return windowUsabilityStatus(of: window.windowElement, appName: window.appName, minimumSize: minimumWindowSize).isUsable
    }

    /// Returns a debug report for why a cached window can or cannot be cycled to.
    func debugUsabilityReport(for window: FocusableWindow) -> (isUsable: Bool, description: String) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        let appReason: String?
        let appDescription: String

        if let app {
            appDescription = "activation=\(String(describing: app.activationPolicy)) hidden=\(app.isHidden)"
            if app.activationPolicy != .regular {
                appReason = "app-not-regular"
            } else if app.isHidden {
                appReason = "app-hidden"
            } else {
                appReason = nil
            }
        } else {
            appDescription = "activation=nil hidden=nil"
            appReason = "app-not-running"
        }

        let status = windowUsabilityStatus(of: window.windowElement, appName: window.appName, minimumSize: minimumWindowSize)
        let isUsable = appReason == nil && status.isUsable
        let reason = appReason ?? status.reason
        let cachedFrame = NSStringFromRect(window.frame)
        let liveFrame = status.axFrame.map { NSStringFromRect($0) } ?? "nil"
        let screenFrame = status.screenFrame.map { NSStringFromRect($0) } ?? "nil"
        let title = status.metadata.title ?? "nil"
        let role = status.metadata.role ?? "nil"
        let subrole = status.metadata.subrole ?? "nil"

        let description = "app=\"\(window.appName)\" pid=\(window.pid) title=\"\(title)\" role=\"\(role)\" subrole=\"\(subrole)\" \(appDescription) cachedAX=\(cachedFrame) liveAX=\(liveFrame) screenFrame=\(screenFrame) usable=\(isUsable) reason=\(reason)"

        return (isUsable, description)
    }

    /// Focuses a specific window (brings its app to front and raises the window).
    func focus(_ window: FocusableWindow) {
        // Raise the window
        AXUIElementSetAttributeValue(window.windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.windowElement, kAXRaiseAction as CFString)

        // Activate the app
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
        }
    }

    /// Returns the AX frame of the currently focused window.
    func getFocusedWindowFrame() -> CGRect? {
        getFocusedWindow()?.frame
    }

    /// Returns the currently focused window for the frontmost app.
    func getFocusedWindow() -> FocusableWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
            return nil
        }

        let window = focusedWindow as! AXUIElement
        let appName = frontApp.localizedName ?? "Unknown"
        guard let frame = usableFrame(of: window, appName: appName) else { return nil }

        return FocusableWindow(
            pid: frontApp.processIdentifier,
            windowElement: window,
            appName: appName,
            frame: frame
        )
    }

    /// Returns the latest AX frame if the window is visible and suitable for overlay/cycling.
    func usableFrame(of window: AXUIElement, appName: String? = nil, minimumSize: CGSize = .zero) -> CGRect? {
        let status = windowUsabilityStatus(of: window, appName: appName, minimumSize: minimumSize)
        return status.isUsable ? status.axFrame : nil
    }

    private func windowUsabilityStatus(of window: AXUIElement, appName: String? = nil, minimumSize: CGSize) -> WindowUsabilityStatus {
        let metadata = axMetadata(of: window)

        if let role = metadata.role, role != kAXWindowRole {
            return WindowUsabilityStatus(isUsable: false, reason: "not-window-role", axFrame: nil, screenFrame: nil, metadata: metadata)
        }

        var minimized: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           let isMinimized = minimized as? Bool,
           isMinimized {
            return WindowUsabilityStatus(isUsable: false, reason: "minimized", axFrame: nil, screenFrame: nil, metadata: metadata)
        }

        guard let axFrame = frame(of: window) else {
            return WindowUsabilityStatus(isUsable: false, reason: "no-ax-frame", axFrame: nil, screenFrame: nil, metadata: metadata)
        }

        guard axFrame.origin.x.isFinite,
              axFrame.origin.y.isFinite,
              axFrame.width.isFinite,
              axFrame.height.isFinite else {
            return WindowUsabilityStatus(isUsable: false, reason: "non-finite-frame", axFrame: axFrame, screenFrame: nil, metadata: metadata)
        }

        guard axFrame.width > minimumSize.width,
              axFrame.height > minimumSize.height else {
            return WindowUsabilityStatus(isUsable: false, reason: "too-small", axFrame: axFrame, screenFrame: nil, metadata: metadata)
        }

        guard let screenFrame = WindowCoordinateConverter.screenFrame(fromAXFrame: axFrame) else {
            return WindowUsabilityStatus(isUsable: false, reason: "coordinate-conversion-failed", axFrame: axFrame, screenFrame: nil, metadata: metadata)
        }

        guard !screenFrame.isNull,
              !screenFrame.isEmpty else {
            return WindowUsabilityStatus(isUsable: false, reason: "empty-screen-frame", axFrame: axFrame, screenFrame: screenFrame, metadata: metadata)
        }

        if isFinderDesktopWindow(appName: appName, metadata: metadata, screenFrame: screenFrame) {
            return WindowUsabilityStatus(isUsable: false, reason: "finder-desktop-window", axFrame: axFrame, screenFrame: screenFrame, metadata: metadata)
        }

        let intersectsVisibleScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(screenFrame)
        }

        guard intersectsVisibleScreen else {
            return WindowUsabilityStatus(isUsable: false, reason: "not-in-visible-screen", axFrame: axFrame, screenFrame: screenFrame, metadata: metadata)
        }

        return WindowUsabilityStatus(isUsable: true, reason: "usable", axFrame: axFrame, screenFrame: screenFrame, metadata: metadata)
    }

    private func axMetadata(of window: AXUIElement) -> WindowAXMetadata {
        WindowAXMetadata(
            title: stringAttribute(kAXTitleAttribute, of: window),
            role: stringAttribute(kAXRoleAttribute, of: window),
            subrole: stringAttribute(kAXSubroleAttribute, of: window)
        )
    }

    private func stringAttribute(_ attribute: String, of window: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func isFinderDesktopWindow(appName: String?, metadata: WindowAXMetadata, screenFrame: CGRect) -> Bool {
        guard isFinderApp(appName) else { return false }

        let trimmedTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let titleIsEmpty = trimmedTitle.isEmpty
        let titleIsDesktop = trimmedTitle == "Desktop" || trimmedTitle == "桌面"
        guard titleIsEmpty || titleIsDesktop else { return false }

        guard let largestVisibleFrame = NSScreen.screens.map(\.visibleFrame).max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return false
        }

        let widerThanSingleScreen = screenFrame.width > largestVisibleFrame.width * 1.1
        let tallerThanSingleScreen = screenFrame.height > largestVisibleFrame.height * 1.1

        return widerThanSingleScreen || tallerThanSingleScreen
    }

    private func isFinderApp(_ appName: String?) -> Bool {
        guard let appName else { return false }
        let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName == "finder" || normalizedName == "访达"
    }

    /// Returns the latest AX frame for a specific window element.
    func frame(of window: AXUIElement) -> CGRect? {
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
}
