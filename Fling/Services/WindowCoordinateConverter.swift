import AppKit

/// Converts between Accessibility window coordinates and AppKit screen coordinates.
enum WindowCoordinateConverter {
    private static var baseScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    /// Converts an AX frame, whose y-axis is measured from the top of the base screen,
    /// to an AppKit screen frame, whose y-axis grows upward from the base screen.
    static func screenFrame(fromAXFrame axFrame: CGRect) -> CGRect? {
        guard let baseScreen else { return nil }
        let baseMaxY = baseScreen.frame.maxY

        return CGRect(
            x: axFrame.origin.x,
            y: baseMaxY - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    /// Converts an AppKit screen frame into the AX coordinate space.
    static func axFrame(fromScreenFrame screenFrame: CGRect) -> CGRect? {
        guard let baseScreen else { return nil }
        let baseMaxY = baseScreen.frame.maxY

        return CGRect(
            x: screenFrame.origin.x,
            y: baseMaxY - screenFrame.origin.y - screenFrame.height,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }
}
