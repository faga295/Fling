import AppKit

/// A transparent overlay window that draws a soft green glow around the focused window.
class BorderOverlayWindow: NSWindow {
    /// Padding around the window to accommodate the glow shadow.
    private let glowPadding: CGFloat = 12
    private let glowView = GlowBorderView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) - 1)
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = glowView
    }

    /// Updates the overlay to surround the given AX-coordinate rect.
    func updateFrame(axFrame: CGRect) {
        guard let convertedFrame = WindowCoordinateConverter.screenFrame(fromAXFrame: axFrame) else {
            hide()
            return
        }

        guard let screen = ScreenManager.shared.screen(for: convertedFrame) else {
            hide()
            return
        }

        let idealOverlayFrame = CGRect(
            x: convertedFrame.origin.x - glowPadding,
            y: convertedFrame.origin.y - glowPadding,
            width: convertedFrame.width + glowPadding * 2,
            height: convertedFrame.height + glowPadding * 2
        )

        let overlayFrame = idealOverlayFrame.intersection(screen.visibleFrame)
        guard !overlayFrame.isNull, !overlayFrame.isEmpty else {
            hide()
            return
        }

        let targetRect = CGRect(
            x: convertedFrame.origin.x - overlayFrame.origin.x,
            y: convertedFrame.origin.y - overlayFrame.origin.y,
            width: convertedFrame.width,
            height: convertedFrame.height
        )

        setFrame(overlayFrame, display: false)
        glowView.targetRect = targetRect
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

/// A view that draws a soft glowing border using NSShadow for a polished look.
class GlowBorderView: NSView {
    private let glowColor: NSColor = NSColor.systemGreen
    private let glowRadius: CGFloat = 8
    private let borderWidth: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    var targetRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              !targetRect.isEmpty else { return }
        context.saveGState()

        let path = NSBezierPath(roundedRect: targetRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Draw outer glow (shadow)
        let shadow = NSShadow()
        shadow.shadowColor = glowColor.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = glowRadius
        shadow.shadowOffset = .zero
        shadow.set()

        // Stroke a thin border with the glow
        glowColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = borderWidth
        path.stroke()

        // Draw a second pass without shadow for a crisp inner edge
        context.restoreGState()
        glowColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}
