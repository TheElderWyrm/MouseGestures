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
    @State private var activationType: ActivationSettings.ActivationType
    @State private var keyboardShortcut: KeyboardTrigger?
    @State private var mouseButton: MouseButtonTrigger?
    @State private var isEnabled: Bool
    @State private var repeatOnHold: Bool
    @State private var repeatInitialDelay: TimeInterval
    @State private var repeatInterval: TimeInterval
    @State private var longPressEnabled: Bool
    @State private var longPressThreshold: TimeInterval
    @State private var actionParameters: [String: AnyCodable]
    
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
            _activationType = State(initialValue: g.activation.activationType)
            _keyboardShortcut = State(initialValue: g.activation.keyboardTrigger)
            _mouseButton = State(initialValue: g.activation.mouseButtonTrigger)
            _isEnabled = State(initialValue: g.activation.isEnabled)
            _repeatOnHold = State(initialValue: g.timing.repeatOnHold)
            _repeatInitialDelay = State(initialValue: g.timing.repeatInitialDelay)
            _repeatInterval = State(initialValue: g.timing.repeatInterval)
            _longPressEnabled = State(initialValue: g.timing.longPressEnabled)
            _longPressThreshold = State(initialValue: g.timing.longPressThreshold)
            _actionParameters = State(initialValue: g.parameters)
        } else {
            _selectedZone = State(initialValue: .topRight)
            _selectedModifiers = State(initialValue: [.command, .control])
            _selectedDragModifier = State(initialValue: .none)
            _selectedActionId = State(initialValue: "")
            _activationType = State(initialValue: .gesture)
            _keyboardShortcut = State(initialValue: nil)
            _mouseButton = State(initialValue: nil)
            _isEnabled = State(initialValue: true)
            _repeatOnHold = State(initialValue: false)
            _repeatInitialDelay = State(initialValue: 0.5)
            _repeatInterval = State(initialValue: 0.5)
            _longPressEnabled = State(initialValue: false)
            _longPressThreshold = State(initialValue: 0.8)
            _actionParameters = State(initialValue: [:])
        }
    }
    
    // Computed helpers for activation type
    private var hasGesture: Bool {
        ActivationSettings(activationType: activationType).hasGesture
    }
    private var hasKeyboard: Bool {
        ActivationSettings(activationType: activationType).hasKeyboard
    }
    private var hasMouseButton: Bool {
        ActivationSettings(activationType: activationType).hasMouseButton
    }
    
    var body: some View {
        VStack(spacing: 0) {
            configurationHeader
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    activationTypeSection
                    triggerConfigurationSection
                    actionSection
                    timingSettingsSection
                }
                .padding()
            }
            
            Divider()
            configurationFooter
        }
        .frame(width: 700, height: 650)
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
            Button("Cancel") { dismiss() }
        }
        .padding()
    }
    
    private var configurationFooter: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Preview:").font(.caption).foregroundColor(.secondary)
                Text(gesturePreviewText).font(.system(.body, design: .monospaced))
            }
            Spacer()
            Button(mode.buttonTitle) { saveGesture() }
                .keyboardShortcut(.return)
                .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Activation Type (top-level choice)
    
    private var activationTypeSection: some View {
        GroupBox("Activation Method") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("How this gesture is triggered:", selection: $activationType) {
                    ForEach(ActivationSettings.ActivationType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 250)
                
                Toggle("Enabled", isOn: $isEnabled)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Trigger Configuration (dynamic)
    
    private var triggerConfigurationSection: some View {
        GroupBox("Trigger") {
            VStack(alignment: .leading, spacing: 16) {
                // Gesture trigger fields
                if hasGesture {
                    gestureTriggerFields
                }
                
                // Keyboard shortcut field
                if hasKeyboard {
                    if hasGesture { Divider() }
                    keyboardTriggerField
                }
                
                // Mouse button field
                if hasMouseButton {
                    if hasGesture || hasKeyboard { Divider() }
                    mouseButtonField
                }
            }
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: activationType)
        }
    }
    
    private var gestureTriggerFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screen Zone Gesture", systemImage: "hand.draw")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            LabeledContent("Zone:") {
                Picker("", selection: $selectedZone) {
                    ForEach(ScreenZone.allCases, id: \.self) { zone in
                        Text(zone.displayName).tag(zone)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            
            LabeledContent("Modifiers:") {
                HStack(spacing: 12) {
                    ModifierToggle(label: "⌘", flag: .command, modifiers: $selectedModifiers)
                    ModifierToggle(label: "⌃", flag: .control, modifiers: $selectedModifiers)
                    ModifierToggle(label: "⌥", flag: .option, modifiers: $selectedModifiers)
                    ModifierToggle(label: "⇧", flag: .shift, modifiers: $selectedModifiers)
                }
            }
            
            LabeledContent("Drag Modifier:") {
                Picker("", selection: $selectedDragModifier) {
                    ForEach(DragModifier.allCases, id: \.self) { drag in
                        Text(drag.displayName).tag(drag)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }
    
    private var keyboardTriggerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcut", systemImage: "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            LabeledContent("Shortcut:") {
                KeyboardShortcutFieldView(shortcut: $keyboardShortcut)
                    .frame(width: 200, height: 24)
            }
        }
    }
    
    private var mouseButtonField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mouse Button", systemImage: "computermouse")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            LabeledContent("Button:") {
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
                .frame(width: 200)
            }
        }
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
        GroupBox("Timing (Optional)") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Repeat on Hold", isOn: $repeatOnHold)
                if repeatOnHold {
                    LabeledContent("Initial Delay:") {
                        HStack {
                            Slider(value: $repeatInitialDelay, in: 0.1...2.0, step: 0.1).frame(width: 150)
                            Text(String(format: "%.1f s", repeatInitialDelay)).frame(width: 50, alignment: .trailing)
                        }
                    }
                    LabeledContent("Repeat Interval:") {
                        HStack {
                            Slider(value: $repeatInterval, in: 0.1...2.0, step: 0.1).frame(width: 150)
                            Text(String(format: "%.1f s", repeatInterval)).frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                
                Toggle("Long Press Action", isOn: $longPressEnabled)
                if longPressEnabled {
                    LabeledContent("Long Press Threshold:") {
                        HStack {
                            Slider(value: $longPressThreshold, in: 0.3...2.0, step: 0.1).frame(width: 150)
                            Text(String(format: "%.1f s", longPressThreshold)).frame(width: 50, alignment: .trailing)
                        }
                    }
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
            )) { Text(label) }
            .toggleStyle(.button)
        }
    }
    
    private var gesturePreviewText: String {
        var parts: [String] = []
        if hasGesture {
            parts.append(selectedZone.displayName)
            var mods: [String] = []
            if selectedModifiers.contains(.command) { mods.append("⌘") }
            if selectedModifiers.contains(.control) { mods.append("⌃") }
            if selectedModifiers.contains(.option) { mods.append("⌥") }
            if selectedModifiers.contains(.shift) { mods.append("⇧") }
            if !mods.isEmpty { parts.append("+"); parts.append(mods.joined()) }
            if selectedDragModifier != .none { parts.append("+"); parts.append(selectedDragModifier.displayName) }
        }
        if hasKeyboard, let kbd = keyboardShortcut {
            if !parts.isEmpty { parts.append("|") }
            parts.append(kbd.displayString)
        }
        if hasMouseButton, let mb = mouseButton {
            if !parts.isEmpty { parts.append("|") }
            parts.append(mb.displayString)
        }
        if let action = PluginManager.shared.getAction(identifier: selectedActionId)?.action {
            parts.append("→"); parts.append(action.name)
        }
        return parts.joined(separator: " ")
    }
    
    private var isValid: Bool {
        guard !selectedActionId.isEmpty else { return false }
        switch activationType {
        case .keyboard, .keyboardMouseButton:
            if keyboardShortcut == nil { return false }
        case .mouseButton, .gestureMouseButton:
            if mouseButton == nil { return false }
        case .all:
            if keyboardShortcut == nil || mouseButton == nil { return false }
        default: break
        }
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
        
        if mode == .add || existingGesture?.id != gesture.id {
            if uiServices.isGestureConflicting(gesture) {
                conflictMessage = "A gesture with this combination of zone, modifiers, and drag already exists."
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
