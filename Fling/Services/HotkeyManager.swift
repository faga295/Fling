import Carbon
import AppKit
import Combine

/// Manages global hotkey registration and handling.
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    enum Action: UInt32 {
        case activatePanel = 1
        case moveToNextDisplay = 2
    }

    var onHotkeyPressed: (() -> Void)?
    var onMoveToNextDisplayHotkeyPressed: (() -> Void)?

    @Published private(set) var keyCode: UInt32 = UInt32(kVK_Space)
    @Published private(set) var carbonModifiers: UInt32 = UInt32(optionKey)
    @Published private(set) var moveToNextDisplayKeyCode: UInt32?
    @Published private(set) var moveToNextDisplayCarbonModifiers: UInt32?

    private var eventHandler: EventHandlerRef?
    private var activatePanelHotkeyRef: EventHotKeyRef?
    private var moveToNextDisplayHotkeyRef: EventHotKeyRef?

    private static let signature = OSType(0x464C4E47) // "FLNG"

    /// Human-readable display string for the current hotkey.
    var displayString: String {
        let modStr = Self.modifiersDisplayString(carbonModifiers)
        let keyStr = Self.keyCodeDisplayString(keyCode)
        return modStr + keyStr
    }

    /// Human-readable display string for the optional next-display hotkey.
    var moveToNextDisplayDisplayString: String {
        guard let keyCode = moveToNextDisplayKeyCode,
              let modifiers = moveToNextDisplayCarbonModifiers else {
            return "Not set"
        }

        return Self.modifiersDisplayString(modifiers) + Self.keyCodeDisplayString(keyCode)
    }

    func register() {
        unregister()

        // Load saved activate-panel hotkey if available
        if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt32,
           let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt32 {
            keyCode = savedKeyCode
            carbonModifiers = savedModifiers
        }

        // Load optional next-display hotkey if available
        if let savedKeyCode = UserDefaults.standard.object(forKey: "moveToNextDisplayHotkeyKeyCode") as? UInt32,
           let savedModifiers = UserDefaults.standard.object(forKey: "moveToNextDisplayHotkeyModifiers") as? UInt32 {
            moveToNextDisplayKeyCode = savedKeyCode
            moveToNextDisplayCarbonModifiers = savedModifiers
        } else {
            moveToNextDisplayKeyCode = nil
            moveToNextDisplayCarbonModifiers = nil
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            guard status == noErr else { return OSStatus(eventNotHandledErr) }

            switch hotkeyID.id {
            case Action.activatePanel.rawValue:
                manager.onHotkeyPressed?()
            case Action.moveToNextDisplay.rawValue:
                manager.onMoveToNextDisplayHotkeyPressed?()
            default:
                return OSStatus(eventNotHandledErr)
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandler)

        registerHotkey(action: .activatePanel, keyCode: keyCode, modifiers: carbonModifiers, ref: &activatePanelHotkeyRef)

        if let moveKeyCode = moveToNextDisplayKeyCode,
           let moveModifiers = moveToNextDisplayCarbonModifiers {
            registerHotkey(action: .moveToNextDisplay, keyCode: moveKeyCode, modifiers: moveModifiers, ref: &moveToNextDisplayHotkeyRef)
        }
    }

    func unregister() {
        unregisterHotkey(&activatePanelHotkeyRef)
        unregisterHotkey(&moveToNextDisplayHotkeyRef)

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = modifiers

        UserDefaults.standard.set(keyCode, forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(modifiers, forKey: "hotkeyModifiers")

        register()
    }

    func updateMoveToNextDisplayHotkey(keyCode: UInt32, modifiers: UInt32) {
        moveToNextDisplayKeyCode = keyCode
        moveToNextDisplayCarbonModifiers = modifiers

        UserDefaults.standard.set(keyCode, forKey: "moveToNextDisplayHotkeyKeyCode")
        UserDefaults.standard.set(modifiers, forKey: "moveToNextDisplayHotkeyModifiers")

        register()
    }

    private func registerHotkey(action: Action, keyCode: UInt32, modifiers: UInt32, ref: inout EventHotKeyRef?) {
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregisterHotkey(_ ref: inout EventHotKeyRef?) {
        if let hotkeyRef = ref {
            UnregisterEventHotKey(hotkeyRef)
            ref = nil
        }
    }

    // MARK: - NSEvent modifiers → Carbon modifiers

    static func nsModifiersToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    // MARK: - Display Strings

    static func modifiersDisplayString(_ carbonMods: UInt32) -> String {
        var result = ""
        if carbonMods & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonMods & UInt32(optionKey) != 0  { result += "⌥" }
        if carbonMods & UInt32(shiftKey) != 0   { result += "⇧" }
        if carbonMods & UInt32(cmdKey) != 0     { result += "⌘" }
        return result
    }

    static func keyCodeDisplayString(_ keyCode: UInt32) -> String {
        let mapping: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "⏎",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_Escape): "Esc",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]

        return mapping[keyCode] ?? "Key(\(keyCode))"
    }
}
