import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var recorder = HotkeyRecorder()
    @State private var recordingAction: HotkeyManager.Action?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Fling Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    hotkeyRow(
                        title: "Activate panel:",
                        action: .activatePanel,
                        displayString: hotkeyManager.displayString
                    ) { keyCode, modifiers in
                        hotkeyManager.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                    }

                    hotkeyRow(
                        title: "Move to next display:",
                        action: .moveToNextDisplay,
                        displayString: hotkeyManager.moveToNextDisplayDisplayString
                    ) { keyCode, modifiers in
                        hotkeyManager.updateMoveToNextDisplayHotkey(keyCode: keyCode, modifiers: modifiers)
                    }

                    if recorder.isRecording {
                        Text("Press a key combination (with ⌃⌥⇧⌘). Press Esc to cancel.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(8)
            }

            GroupBox("Key Bindings") {
                VStack(alignment: .leading, spacing: 8) {
                    keyRow("h", description: "Snap to left half")
                    keyRow("l", description: "Snap to right half")
                    keyRow("k", description: "Snap to top half")
                    keyRow("j", description: "Snap to bottom half")
                    keyRow("Space", description: "Maximize window")
                    Divider()
                    keyRow("H (Shift+h)", description: "Move to left display")
                    keyRow("L (Shift+l)", description: "Move to right display")
                    Divider()
                    keyRow("Esc / q", description: "Dismiss panel")
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400, height: 460)
    }

    @ViewBuilder
    private func hotkeyRow(
        title: String,
        action: HotkeyManager.Action,
        displayString: String,
        onRecorded: @escaping (UInt32, UInt32) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            Button(action: {
                if recorder.isRecording {
                    recorder.stopRecording()
                    recordingAction = nil
                } else {
                    recordingAction = action
                    recorder.startRecording { keyCode, modifiers in
                        onRecorded(keyCode, modifiers)
                        recordingAction = nil
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if recorder.isRecording && recordingAction == action {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Type shortcut...")
                            .foregroundColor(.secondary)
                    } else {
                        Text(displayString)
                            .fontWeight(.medium)
                    }
                }
                .frame(minWidth: 140)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func keyRow(_ key: String, description: String) -> some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 100, alignment: .leading)
            Text(description)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Hotkey Recorder

class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false

    private var localMonitor: Any?
    private var onRecorded: ((UInt32, UInt32) -> Void)?

    func startRecording(onRecorded: @escaping (UInt32, UInt32) -> Void) {
        self.onRecorded = onRecorded
        isRecording = true

        // Temporarily unregister global hotkey so it doesn't fire during recording
        HotkeyManager.shared.unregister()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func stopRecording() {
        isRecording = false
        onRecorded = nil

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Re-register the global hotkey
        HotkeyManager.shared.register()
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)

        // Escape cancels recording
        if keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return true
        }

        // Require at least one modifier key (⌃⌥⇧⌘)
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !modifiers.isEmpty else { return false }

        let carbonMods = HotkeyManager.nsModifiersToCarbonModifiers(modifiers)

        onRecorded?(keyCode, carbonMods)
        stopRecording()
        return true
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
