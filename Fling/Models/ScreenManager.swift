import AppKit

/// Represents the detected layout state of a window on a screen.
enum WindowLayout {
    case maximized
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case custom // Not a recognized snap position
}

/// Manages screen ordering and provides wrap-around navigation between displays.
class ScreenManager {
    static let shared = ScreenManager()

    /// Tolerance for comparing frame positions (in points).
    private let tolerance: CGFloat = 10

    /// Returns all screens sorted by their x-coordinate (left to right).
    var orderedScreens: [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// Returns the screen containing the given window frame.
    func screen(for windowFrame: CGRect) -> NSScreen? {
        let screens = orderedScreens
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.first { $0.frame.contains(center) }
            ?? screens.first
    }

    /// Returns the index of the given screen in the ordered list.
    func index(of screen: NSScreen) -> Int? {
        orderedScreens.firstIndex(of: screen)
    }

    /// Returns the next screen to the left (with wrap-around).
    func screenToLeft(of current: NSScreen) -> NSScreen? {
        let screens = orderedScreens
        guard screens.count > 1,
              let idx = screens.firstIndex(of: current) else { return nil }
        let targetIdx = idx == 0 ? screens.count - 1 : idx - 1
        return screens[targetIdx]
    }

    /// Returns the next screen to the right (with wrap-around).
    func screenToRight(of current: NSScreen) -> NSScreen? {
        let screens = orderedScreens
        guard screens.count > 1,
              let idx = screens.firstIndex(of: current) else { return nil }
        let targetIdx = idx == screens.count - 1 ? 0 : idx + 1
        return screens[targetIdx]
    }

    /// Detects the current layout state of a window on a given screen.
    /// Uses coverage-based detection: if the window covers 85%+ of a layout zone's width
    /// AND the position/height match closely, it's a match.
    /// This handles apps with max-width constraints that can't fill the full screen.
    func detectLayout(windowFrame: CGRect, on screen: NSScreen) -> WindowLayout {
        let v = screen.visibleFrame

        let layouts: [(WindowLayout, CGRect)] = [
            (.maximized, v),
            (.leftHalf, CGRect(x: v.origin.x, y: v.origin.y, width: v.width / 2, height: v.height)),
            (.rightHalf, CGRect(x: v.origin.x + v.width / 2, y: v.origin.y, width: v.width / 2, height: v.height)),
            (.topHalf, CGRect(x: v.origin.x, y: v.origin.y + v.height / 2, width: v.width, height: v.height / 2)),
            (.bottomHalf, CGRect(x: v.origin.x, y: v.origin.y, width: v.width, height: v.height / 2)),
        ]

        for (layout, zone) in layouts {
            // Window must start near the zone's origin
            let originClose = abs(windowFrame.origin.x - zone.origin.x) < tolerance &&
                              abs(windowFrame.origin.y - zone.origin.y) < tolerance

            // Window height must match zone height closely
            let heightClose = abs(windowFrame.height - zone.height) < tolerance

            // Window width must be at least 85% of zone width (handles app max-width limits)
            let widthCoverage = windowFrame.width / zone.width

            if originClose && heightClose && widthCoverage >= 0.85 {
                return layout
            }
        }

        return .custom
    }

    /// Calculates the target frame when moving a window to another screen.
    /// If the window is in a recognized snap position, apply the same layout on the target screen.
    /// Otherwise, preserve the relative position and size ratio.
    func targetFrame(for windowFrame: CGRect, from sourceScreen: NSScreen, to targetScreen: NSScreen) -> CGRect {
        let layout = detectLayout(windowFrame: windowFrame, on: sourceScreen)
        let tv = targetScreen.visibleFrame

        switch layout {
        case .maximized:
            return tv
        case .leftHalf:
            return CGRect(x: tv.origin.x, y: tv.origin.y, width: tv.width / 2, height: tv.height)
        case .rightHalf:
            return CGRect(x: tv.origin.x + tv.width / 2, y: tv.origin.y, width: tv.width / 2, height: tv.height)
        case .topHalf:
            return CGRect(x: tv.origin.x, y: tv.origin.y + tv.height / 2, width: tv.width, height: tv.height / 2)
        case .bottomHalf:
            return CGRect(x: tv.origin.x, y: tv.origin.y, width: tv.width, height: tv.height / 2)
        case .custom:
            // Fallback: preserve relative position and size ratio
            let sv = sourceScreen.visibleFrame
            let relX = (windowFrame.origin.x - sv.origin.x) / sv.width
            let relY = (windowFrame.origin.y - sv.origin.y) / sv.height
            let relW = windowFrame.width / sv.width
            let relH = windowFrame.height / sv.height
            return CGRect(
                x: tv.origin.x + relX * tv.width,
                y: tv.origin.y + relY * tv.height,
                width: relW * tv.width,
                height: relH * tv.height
            )
        }
    }

    // MARK: - Private

    private func approxEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance &&
        abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.width - b.width) < tolerance &&
        abs(a.height - b.height) < tolerance
    }
}
