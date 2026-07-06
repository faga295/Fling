import AppKit
import ApplicationServices

/// Manages Accessibility permission checking and requesting.
class PermissionManager {
    static let shared = PermissionManager()

    var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        if !isAccessibilityEnabled {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
}
