import Foundation

enum WindowAction: String, CaseIterable {
    case left       // h — snap to left half
    case right      // l — snap to right half
    case top        // k — snap to top half
    case bottom     // j — snap to bottom half
    case maximize   // space — maximize
    case moveLeft   // H — move to left display
    case moveRight  // L — move to right display

    var displayName: String {
        switch self {
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .top: return "Top Half"
        case .bottom: return "Bottom Half"
        case .maximize: return "Maximize"
        case .moveLeft: return "Move to Left Display"
        case .moveRight: return "Move to Right Display"
        }
    }

    var iconName: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .moveLeft: return "macwindow.on.rectangle"
        case .moveRight: return "macwindow.on.rectangle"
        }
    }

    var keyLabel: String {
        switch self {
        case .left: return "h"
        case .right: return "l"
        case .top: return "k"
        case .bottom: return "j"
        case .maximize: return "⎵"
        case .moveLeft: return "H"
        case .moveRight: return "L"
        }
    }
}
