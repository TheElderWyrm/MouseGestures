import SwiftUI
import AppKit

// MARK: - Add/Edit Gesture Sheet

struct GestureConfigurationSheet: View {
    let mode: Mode
    let existingGesture: Gesture?
    let onSave: (Gesture) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    // Gesture configuration state
    @State private var selectedZone: ScreenZone
    @State private var selectedModifiers: NSEvent.ModifierFlags
    @State private var selectedDragModifier: DragModifier
    @State private var selectedActionId: String
    @State private var keyboardShortcut: KeyboardTrigger?
    @State private var mouseButton: MouseButtonTrigger?
    @State private var isEnabled: Bool
    @State private var repeatOnHold: Bool
    @State private var repeatInitialDelay: TimeInterval
    @State private var repeatInterval: TimeInterval
    @State private var longPressEnabled: Bool
    @State private var longPressThreshold: TimeInterval
    @State private var actionParameters: [String: AnyCodable]
    
    // New: Individual trigger type toggles
    @State private var useGesture: Bool
    @State private var useKeyboard: Bool
    @State private var useMouseButton: Bool
    
    // UI State
    @State private var showingConflictAlert = false
    @State private var conflictMessage = ""
    
    enum Mode {
        case add, edit
        var title: String { self == .add ? "Add Gesture" : "Edit Gesture" }
        var buttonTitle: String { self == .add ? "Add" : "Save" }
    }
    
    init(mode: Mode, existingGesture: Gesture? = nil, onSave: @escaping (Gesture) -> Void) {
        self.mode = mode
        self.existingGesture = existingGesture
        self.onSave = onSave
        
        if let g = existingGesture {
            _selectedZone = State(initialValue: g.zone)
            _selectedModifiers = State(initialValue: g.modifiers)
            _selectedDragModifier = State(initialValue: g.dragModifier)
            _selectedActionId = State(initialValue: g.actionIdentifier)
            _keyboardShortcut = State(initialValue: g.activation.keyboardTrigger)
            _mouseButton = State(initialValue: g.activation.mouseButtonTrigger)
            _isEnabled = State(initialValue: g.activation.isEnabled)
            _repeatOnHold = State(initialValue: g.timing.repeatOnHold)
            _repeatInitialDelay = State(initialValue: g.timing.repeatInitialDelay)
            _repeatInterval = State(initialValue: g.timing.repeatInterval)
            _longPressEnabled = State(initialValue: g.timing.longPressEnabled)
            _longPressThreshold = State(initialValue: g.timing.longPressThreshold)
            _actionParameters = State(initialValue: g.parameters)
            
            // Initialize trigger toggles from activation type
            let settings = g.activation
            _useGesture = State(initialValue: settings.hasGesture)
            _useKeyboard = State(initialValue: settings.hasKeyboard)
            _useMouseButton = State(initialValue: settings.hasMouseButton)
        } else {
            _selectedZone = State(initialValue: .topRight)
            _selectedModifiers = State(initialValue: [.command, .control])
            _selectedDragModifier = State(initialValue: .none)
            _selectedActionId = State(initialValue: "")
            _keyboardShortcut = State(initialValue: nil)
            _mouseButton = State(initialValue: nil)
            _isEnabled = State(initialValue: true)
            _repeatOnHold = State(initialValue: false)
            _repeatInitialDelay = State(initialValue: 0.5)
            _repeatInterval = State(initialValue: 0.5)
            _longPressEnabled = State(initialValue: false)
            _longPressThreshold = State(initialValue: 0.8)
            _actionParameters = State(initialValue: [:])
            
            // Default: gesture only
            _useGesture = State(initialValue: true)
            _useKeyboard = State(initialValue: false)
            _useMouseButton = State(initialValue: false)
        }
    }
    
    // Computed activation type from individual toggles
    private var activationType: ActivationSettings.ActivationType {
        switch (useGesture, useKeyboard, useMouseButton) {
        case (true, false, false): return .gesture
        case (false, true, false): return .keyboard
        case (false, false, true): return .mouseButton
        case (true, true, false): return .both
        case (true, false, true): return .gestureMouseButton
        case (false, true, true): return .keyboardMouseButton
        case (true, true, true): return .all
        default: return .gesture // Fallback if nothing selected
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            configurationHeader
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Prominent preview at top
                    gesturePreviewCard
                    
                    activationMethodSection
                    triggerConfigurationSection
                    actionSection
                    timingSettingsSection
                }
                .padding()
            }
            
            Divider()
            configurationFooter
        }
        .frame(width: 750, height: 680)
        .alert("Gesture Conflict", isPresented: $showingConflictAlert) {
            Button("OK") {}
        } message: {
            Text(conflictMessage)
        }
    }
    
    // MARK: - Header / Footer
    
    private var configurationHeader: some View {
        HStack {
            Text(mode.title).font(.title2).bold()
            Spacer()
            Toggle("Enabled", isOn: $isEnabled)
                .toggleStyle(.switch)
            Button("Cancel") { dismiss() }
        }
        .padding()
    }
    
    private var configurationFooter: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button(mode.buttonTitle) {
                saveGesture()
            }
            .keyboardShortcut(.return)
            .disabled(!isValid)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Preview Card
    
    private var gesturePreviewCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    Text("Preview")
                        .font(.headline)
                    Spacer()
                }
                
                Text(gesturePreviewText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Activation Method (Improved)
    
    private var activationMethodSection: some View {
        GroupBox("Trigger Methods") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select which methods can activate this gesture:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    TriggerMethodToggle(
                        isOn: $useGesture,
                        icon: "hand.draw",
                        title: "Screen Zone Gesture",
                        description: "Activate by clicking and dragging in a screen zone"
                    )
                    
                    TriggerMethodToggle(
                        isOn: $useKeyboard,
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Activate with a keyboard combination"
                    )
                    
                    TriggerMethodToggle(
                        isOn: $useMouseButton,
                        icon: "computermouse",
                        title: "Mouse Button",
                        description: "Activate with a mouse button click"
                    )
                }
                
                // Validation hint
                if !useGesture && !useKeyboard && !useMouseButton {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("At least one trigger method must be selected")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Trigger Configuration (dynamic)
    
    private var triggerConfigurationSection: some View {
        GroupBox("Trigger Configuration") {
            VStack(alignment: .leading, spacing: 16) {
                if !useGesture && !useKeyboard && !useMouseButton {
                    Text("Select at least one trigger method above to configure")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Gesture trigger fields
                    if useGesture {
                        gestureTriggerFields
                    }
                    
                    // Keyboard shortcut field
                    if useKeyboard {
                        if useGesture { Divider().padding(.vertical, 4) }
                        keyboardTriggerField
                    }
                    
                    // Mouse button field
                    if useMouseButton {
                        if useGesture || useKeyboard { Divider().padding(.vertical, 4) }
                        mouseButtonField
                    }
                }
            }
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: useGesture)
            .animation(.easeInOut(duration: 0.2), value: useKeyboard)
            .animation(.easeInOut(duration: 0.2), value: useMouseButton)
        }
    }
    
    private var gestureTriggerFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.draw")
                    .foregroundColor(.blue)
                Text("Screen Zone Gesture")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Zone:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedZone) {
                        ForEach(ScreenZone.allCases, id: \.self) { zone in
                            Text(zone.displayName).tag(zone)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    Spacer()
                }
                
                HStack {
                    Text("Modifiers:")
                        .frame(width: 100, alignment: .trailing)
                    HStack(spacing: 10) {
                        ModifierToggle(label: "⌘", flag: .command, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⌃", flag: .control, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⌥", flag: .option, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⇧", flag: .shift, modifiers: $selectedModifiers)
                    }
                    Spacer()
                }
                
                HStack {
                    Text("Drag Type:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedDragModifier) {
                        ForEach(DragModifier.allCases, id: \.self) { drag in
                            Text(drag.displayName).tag(drag)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    Spacer()
                }
            }
            .padding(.leading, 24)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var keyboardTriggerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundColor(.green)
                Text("Keyboard Shortcut")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            HStack {
                Text("Shortcut:")
                    .frame(width: 100, alignment: .trailing)
                KeyboardShortcutFieldView(shortcut: $keyboardShortcut)
                    .frame(width: 220, height: 28)
                Spacer()
            }
            .padding(.leading, 24)
            
            if useKeyboard && keyboardShortcut == nil {
                HStack {
                    Spacer().frame(width: 124)
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Keyboard shortcut required")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var mouseButtonField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "computermouse")
                    .foregroundColor(.purple)
                Text("Mouse Button")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            HStack {
                Text("Button:")
                    .frame(width: 100, alignment: .trailing)
                Picker("", selection: Binding<MouseButtonTrigger.MouseButton>(
                    get: { mouseButton?.button ?? .left },
                    set: { btn in
                        if mouseButton != nil { mouseButton?.button = btn }
                        else { mouseButton = MouseButtonTrigger(button: btn, modifiers: []) }
                    }
                )) {
                    Text("Left").tag(MouseButtonTrigger.MouseButton.left)
                    Text("Right").tag(MouseButtonTrigger.MouseButton.right)
                    Text("Middle").tag(MouseButtonTrigger.MouseButton.middle)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
            }
            .padding(.leading, 24)
            
            if useMouseButton && mouseButton == nil {
                HStack {
                    Spacer().frame(width: 124)
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Mouse button configuration required")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Action (shared component)
    
    private var actionSection: some View {
        ActionSelectionView(
            selectedActionId: $selectedActionId,
            actionParameters: $actionParameters
        )
    }
    
    // MARK: - Timing
    
    private var timingSettingsSection: some View {
        GroupBox("Timing Options") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Repeat on Hold", isOn: $repeatOnHold)
                if repeatOnHold {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Initial Delay:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $repeatInitialDelay, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", repeatInitialDelay))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                        
                        HStack {
                            Text("Repeat Interval:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $repeatInterval, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", repeatInterval))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
                
                Divider()
                
                Toggle("Long Press Action", isOn: $longPressEnabled)
                if longPressEnabled {
                    HStack {
                        Text("Threshold:")
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $longPressThreshold, in: 0.3...2.0, step: 0.1)
                            .frame(width: 200)
                        Text(String(format: "%.1f s", longPressThreshold))
                            .frame(width: 50, alignment: .trailing)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helpers
    
    struct ModifierToggle: View {
        let label: String
        let flag: NSEvent.ModifierFlags
        @Binding var modifiers: NSEvent.ModifierFlags
        
        var body: some View {
            Toggle(isOn: Binding(
                get: { modifiers.contains(flag) },
                set: { if $0 { modifiers.insert(flag) } else { modifiers.remove(flag) } }
            )) {
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
            }
            .toggleStyle(.button)
        }
    }
    
    struct TriggerMethodToggle: View {
        @Binding var isOn: Bool
        let icon: String
        let title: String
        let description: String
        
        var body: some View {
            HStack(spacing: 12) {
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .foregroundColor(isOn ? .blue : .secondary)
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isOn ? .primary : .secondary)
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(isOn ? Color.blue.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    private var gesturePreviewText: String {
        var parts: [String] = []
        
        if useGesture {
            var gestureParts: [String] = [selectedZone.displayName]
            var mods: [String] = []
            if selectedModifiers.contains(.command) { mods.append("⌘") }
            if selectedModifiers.contains(.control) { mods.append("⌃") }
            if selectedModifiers.contains(.option) { mods.append("⌥") }
            if selectedModifiers.contains(.shift) { mods.append("⇧") }
            if !mods.isEmpty { gestureParts.append("+"); gestureParts.append(mods.joined()) }
            if selectedDragModifier != .none { 
                gestureParts.append("+")
                gestureParts.append(selectedDragModifier.displayName) 
            }
            parts.append(gestureParts.joined(separator: " "))
        }
        
        if useKeyboard {
            if let kbd = keyboardShortcut {
                parts.append(kbd.displayString)
            } else {
                parts.append("[Keyboard: Not Set]")
            }
        }
        
        if useMouseButton {
            if let mb = mouseButton {
                parts.append(mb.displayString)
            } else {
                parts.append("[Mouse: Not Set]")
            }
        }
        
        if parts.isEmpty {
            parts.append("[No trigger methods selected]")
        }
        
        let triggerText = parts.joined(separator: " | ")
        
        if let action = PluginManager.shared.getAction(identifier: selectedActionId)?.action {
            return "\(triggerText) → \(action.name)"
        } else if !selectedActionId.isEmpty {
            return "\(triggerText) → [Action: \(selectedActionId)]"
        } else {
            return "\(triggerText) → [No action selected]"
        }
    }
    
    private var isValid: Bool {
        // Must have at least one trigger method
        guard useGesture || useKeyboard || useMouseButton else { return false }
        
        // Must have an action
        guard !selectedActionId.isEmpty else { return false }
        
        // Validate required fields for each enabled trigger
        if useKeyboard && keyboardShortcut == nil { return false }
        if useMouseButton && mouseButton == nil { return false }
        
        return true
    }
    
    private func saveGesture() {
        let gesture = Gesture(
            zone: selectedZone,
            modifiers: selectedModifiers,
            dragModifier: selectedDragModifier,
            actionIdentifier: selectedActionId,
            parameters: actionParameters,
            keyboardTrigger: keyboardShortcut,
            mouseButtonTrigger: mouseButton,
            activationType: activationType,
            isEnabled: isEnabled,
            repeatOnHold: repeatOnHold,
            repeatInitialDelay: repeatInitialDelay,
            repeatInterval: repeatInterval,
            longPressEnabled: longPressEnabled,
            longPressThreshold: longPressThreshold
        )
        
        if mode == .add || existingGesture?.triggerKey != gesture.triggerKey {
            if uiServices.isGestureConflicting(gesture) {
                conflictMessage = "A gesture with this zone, modifier, and drag combination already exists. Each trigger combination can only be assigned one action."
                showingConflictAlert = true
                return
            }
        }
        
        onSave(gesture)
        dismiss()
    }
}

// MARK: - KeyboardShortcutFieldView

struct KeyboardShortcutFieldView: NSViewRepresentable {
    @Binding var shortcut: KeyboardTrigger?
    
    func makeNSView(context: Context) -> KeyboardShortcutField {
        let field = KeyboardShortcutField()
        field.onShortcutCapture = { cap in
            var mods = NSEvent.ModifierFlags()
            if cap.modifiers.contains(.maskCommand) { mods.insert(.command) }
            if cap.modifiers.contains(.maskControl) { mods.insert(.control) }
            if cap.modifiers.contains(.maskAlternate) { mods.insert(.option) }
            if cap.modifiers.contains(.maskShift) { mods.insert(.shift) }
            shortcut = KeyboardTrigger(keyCode: cap.keyCode, modifiers: mods, displayString: cap.displayString)
        }
        return field
    }
    
    func updateNSView(_ nsView: KeyboardShortcutField, context: Context) {
        if let t = shortcut {
            var cgFlags = CGEventFlags(rawValue: 0)
            if t.modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
            if t.modifiers.contains(.control) { cgFlags.insert(.maskControl) }
            if t.modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
            if t.modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
            nsView.capturedShortcut = KeyboardShortcut(keyCode: t.keyCode, modifiers: cgFlags, displayString: t.displayString)
            nsView.stringValue = t.displayString
        } else {
            nsView.capturedShortcut = nil
            nsView.stringValue = ""
        }
    }
}

// MARK: - Convenience Wrappers

struct AddGestureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        GestureConfigurationSheet(mode: .add) { gesture in
            _ = uiServices.addGesture(gesture)
        }
    }
}

struct EditGestureSheet: View {
    let gesture: Gesture
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        GestureConfigurationSheet(mode: .edit, existingGesture: gesture) { updated in
            _ = uiServices.updateGesture(oldGesture: gesture, newGesture: updated)
        }
    }
}
