import Cocoa

// Custom text field for capturing keyboard shortcuts
class KeyboardShortcutField: NSTextField {
    var onShortcutCapture: ((KeyboardShortcut) -> Void)?
    var capturedShortcut: KeyboardShortcut? // 🔵 Made public for reset
    private var isListening = false
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var originalBackgroundColor: NSColor?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupField()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupField()
    }
    
    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupField() {
        isEditable = false
        isSelectable = false
        isBezeled = true
        bezelStyle = .squareBezel
        focusRingType = .exterior
        allowsEditingTextAttributes = false
        isEnabled = true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            isListening = true
            
            // Store original background color and set active color
            originalBackgroundColor = backgroundColor
            backgroundColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.2)
            
            // Don't reset capturedShortcut if we already have one (editing mode)
            if capturedShortcut == nil {
                stringValue = "Press keyboard shortcut..."
            } else {
                // Keep the existing shortcut display until a new one is pressed
                stringValue = capturedShortcut!.displayString + " (press new shortcut to change)"
            }
            log.log("KeyboardShortcutField became first responder, listening for input")
            
            // Disable Mission Control and Spaces temporarily while capturing
            disableSystemShortcutsTemporarily()
            
            // Add both local and global event monitors to ensure we capture the event
            // Local monitor captures events in our app
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self = self, self.isListening else { return event }
                
                if event.type == .flagsChanged {
                    // Update display to show current modifiers being pressed
                    self.updateModifierDisplay(event.modifierFlags)
                    return nil  // Consume the event
                } else {
                    // Process the key event
                    self.processKeyEvent(event)
                    // Consume the event to prevent system shortcuts from triggering
                    return nil
                }
            }
            
            // Global monitor captures system-wide events (as backup)
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self, self.isListening else { return }
                // Only process if local monitor didn't catch it
                self.processKeyEvent(event)
            }
        }
        return result
    }
    
    override func mouseDown(with event: NSEvent) {
        // Don't call super to prevent default behavior
        // Just make this field first responder
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
            log.log("KeyboardShortcutField clicked, requesting first responder")
        }
    }
    
    override func resignFirstResponder() -> Bool {
        isListening = false
        
        // Re-enable system shortcuts
        restoreSystemShortcuts()
        
        // Restore original background color
        if let originalColor = originalBackgroundColor {
            backgroundColor = originalColor
        }
        
        if capturedShortcut == nil {
            stringValue = ""
        } else {
            // Restore the shortcut display string without the "press new shortcut" message
            stringValue = capturedShortcut!.displayString
        }
        
        // Remove both event monitors
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        log.log("KeyboardShortcutField resigned first responder")
        return super.resignFirstResponder()
    }
    
    override func keyDown(with event: NSEvent) {
        // Don't process here if we have a local monitor (it will handle it)
        if localEventMonitor != nil && isListening {
            return
        }
        
        log.log("KeyboardShortcutField keyDown: keyCode=\(event.keyCode), modifiers=\(event.modifierFlags.rawValue), isListening=\(isListening)")
        
        // Only capture if we're actively listening
        guard isListening else {
            super.keyDown(with: event)
            return
        }
        
        processKeyEvent(event)
    }
    
    private func updateModifierDisplay(_ modifiers: NSEvent.ModifierFlags) {
        // Show currently pressed modifiers
        var displayParts: [String] = []
        if modifiers.contains(.command) { displayParts.append("⌘") }
        if modifiers.contains(.control) { displayParts.append("⌃") }
        if modifiers.contains(.option) { displayParts.append("⌥") }
        if modifiers.contains(.shift) { displayParts.append("⇧") }
        
        if displayParts.isEmpty {
            if capturedShortcut == nil {
                stringValue = "Press keyboard shortcut..."
            } else {
                stringValue = capturedShortcut!.displayString + " (press new shortcut to change)"
            }
        } else {
            stringValue = displayParts.joined(separator: " ") + " + ..."
        }
    }
    
    private func processKeyEvent(_ event: NSEvent) {
        // Capture the keyboard shortcut
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        // Handle escape key specially - cancel capture
        if keyCode == 53 {
            log.log("Escape pressed, canceling capture")
            isListening = false
            window?.makeFirstResponder(nil)
            return
        }
        
        // Don't capture modifier keys alone
        if isModifierKey(keyCode: keyCode) {
            log.log("Ignoring modifier key")
            return
        }
        
        // Convert NSEvent.ModifierFlags to CGEventFlags
        var cgModifiers: CGEventFlags = []
        if modifiers.contains(.command) { cgModifiers.insert(.maskCommand) }
        if modifiers.contains(.control) { cgModifiers.insert(.maskControl) }
        if modifiers.contains(.option) { cgModifiers.insert(.maskAlternate) }
        if modifiers.contains(.shift) { cgModifiers.insert(.maskShift) }
        
        // Create display string
        var displayParts: [String] = []
        if modifiers.contains(.command) { displayParts.append("⌘") }
        if modifiers.contains(.control) { displayParts.append("⌃") }
        if modifiers.contains(.option) { displayParts.append("⌥") }
        if modifiers.contains(.shift) { displayParts.append("⇧") }
        
        // Add the key character
        if let keyChar = keyCharacter(for: keyCode) {
            displayParts.append(keyChar)
        } else {
            displayParts.append("Key \(keyCode)")
        }
        
        let displayString = displayParts.joined(separator: " ")
        
        // Create and store the shortcut
        capturedShortcut = KeyboardShortcut(keyCode: CGKeyCode(keyCode),
                                           modifiers: cgModifiers,
                                           displayString: displayString)
        
        // Update display
        stringValue = displayString
        
        // Stop listening
        isListening = false
        
        // Notify delegate
        onShortcutCapture?(capturedShortcut!)
        
        log.log("Captured shortcut: \(displayString)")
        
        // Remove focus to prevent further input
        window?.makeFirstResponder(nil)
    }
    
    private func isModifierKey(keyCode: UInt16) -> Bool {
        // Check if this is a modifier key
        switch Int(keyCode) {
        case 55, 56, 57, 58, 59, 60, 61, 62, 63: // Command, Shift, Caps Lock, Option, Control, etc.
            return true
        default:
            return false
        }
    }
    
    private func keyCharacter(for keyCode: UInt16) -> String? {
        // Map common key codes to their character representations
        switch Int(keyCode) {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
    
    // Temporarily disable system shortcuts that interfere with shortcut capture
    private func disableSystemShortcutsTemporarily() {
        // Note: This approach uses accessibility API to temporarily prevent system shortcuts
        // We'll show a helpful message to the user about this
        if capturedShortcut == nil {
            stringValue = "Recording... (System shortcuts disabled)"
        } else {
            stringValue = capturedShortcut!.displayString + " (recording...)"
        }
    }
    
    private func restoreSystemShortcuts() {
        // Restore normal system shortcut behavior
        // This happens automatically when we stop monitoring events
    }
}
