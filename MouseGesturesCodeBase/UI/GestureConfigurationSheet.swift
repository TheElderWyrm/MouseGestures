import SwiftUI
import AppKit

// MARK: - Add/Edit Gesture Sheet (Component-Based)

struct GestureConfigurationSheet: View {
    let mode: Mode
    let existingGesture: Gesture?
    let onSave: (Gesture) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    // Component-based state
    @State private var components: GestureActivationComponents
    @State private var selectedActionId: String
    @State private var actionParameters: [String: AnyCodable]
    @State private var timing: TimingSettings
    @State private var isEnabled: Bool
    
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
            var gesture = g
            _components = State(initialValue: gesture.getComponents())
            _selectedActionId = State(initialValue: g.actionIdentifier)
            _actionParameters = State(initialValue: g.parameters)
            _timing = State(initialValue: g.timing)
            _isEnabled = State(initialValue: g.isEnabled)
        } else {
            // Default: screen zone with modifiers
            var defaultComponents = GestureActivationComponents()
            defaultComponents.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: [.command, .control])
            defaultComponents.screenZone = ScreenZoneConfig(isEnabled: true, zone: .topRight)
            _components = State(initialValue: defaultComponents)
            _selectedActionId = State(initialValue: "")
            _actionParameters = State(initialValue: [:])
            _timing = State(initialValue: TimingSettings())
            _isEnabled = State(initialValue: true)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            configurationHeader
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    gesturePreviewCard
                    activationComponentsSection
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
                
                Text(components.previewString + actionPreview)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var actionPreview: String {
        if let action = PluginManager.shared.getAction(identifier: selectedActionId)?.action {
            return " → \(action.name)"
        } else if !selectedActionId.isEmpty {
            return " → [Action: \(selectedActionId)]"
        } else {
            return " → [No action selected]"
        }
    }
    
    // MARK: - Activation Components Section
    
    private var activationComponentsSection: some View {
        GroupBox("Trigger Configuration") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure which conditions must be met to activate this gesture:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    // Modifier Keys Component
                    ComponentToggleCard(
                        icon: "command.square",
                        title: "Modifier Keys",
                        description: "Require specific modifier keys to be held",
                        isEnabled: Binding(
                            get: { components.modifierKey?.isEnabled ?? false },
                            set: { enabled in
                                if enabled {
                                    if components.modifierKey == nil {
                                        components.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: [.command])
                                    } else {
                                        components.modifierKey?.isEnabled = true
                                    }
                                } else {
                                    components.modifierKey?.isEnabled = false
                                }
                            }
                        )
                    )
                    
                    if components.modifierKey?.isEnabled == true {
                        modifierKeyConfigView
                    }
                    
                    // Screen Zone Component
                    ComponentToggleCard(
                        icon: "square.grid.3x3",
                        title: "Screen Zone",
                        description: "Activate in a specific screen zone",
                        isEnabled: Binding(
                            get: { components.screenZone?.isEnabled ?? false },
                            set: { enabled in
                                if enabled {
                                    if components.screenZone == nil {
                                        components.screenZone = ScreenZoneConfig(isEnabled: true, zone: .topRight)
                                    } else {
                                        components.screenZone?.isEnabled = true
                                    }
                                } else {
                                    components.screenZone?.isEnabled = false
                                }
                            }
                        )
                    )
                    
                    if components.screenZone?.isEnabled == true {
                        screenZoneConfigView
                    }
                    
                    // Drag Type Component
                    ComponentToggleCard(
                        icon: "hand.draw",
                        title: "Drag Type",
                        description: "Require dragging with a specific mouse button",
                        isEnabled: Binding(
                            get: { components.dragType?.isEnabled ?? false },
                            set: { enabled in
                                if enabled {
                                    if components.dragType == nil {
                                        components.dragType = DragTypeConfig(isEnabled: true, dragType: .leftDrag)
                                    } else {
                                        components.dragType?.isEnabled = true
                                    }
                                } else {
                                    components.dragType?.isEnabled = false
                                }
                            }
                        )
                    )
                    
                    if components.dragType?.isEnabled == true {
                        dragTypeConfigView
                    }
                    
                    // Mouse Button Component
                    ComponentToggleCard(
                        icon: "computermouse",
                        title: "Mouse Button",
                        description: "Activate with a mouse button click",
                        isEnabled: Binding(
                            get: { components.mouseButton?.isEnabled ?? false },
                            set: { enabled in
                                if enabled {
                                    if components.mouseButton == nil {
                                        components.mouseButton = MouseButtonConfig(isEnabled: true, button: .left)
                                    } else {
                                        components.mouseButton?.isEnabled = true
                                    }
                                } else {
                                    components.mouseButton?.isEnabled = false
                                }
                            }
                        )
                    )
                    
                    if components.mouseButton?.isEnabled == true {
                        mouseButtonConfigView
                    }
                    
                    // Keyboard Shortcut Component
                    ComponentToggleCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Activate with a keyboard combination",
                        isEnabled: Binding(
                            get: { components.keyboardShortcut?.isEnabled ?? false },
                            set: { enabled in
                                if enabled {
                                    if components.keyboardShortcut == nil {
                                        components.keyboardShortcut = KeyboardShortcutConfig(isEnabled: true, keyboardTrigger: nil)
                                    } else {
                                        components.keyboardShortcut?.isEnabled = true
                                    }
                                } else {
                                    components.keyboardShortcut?.isEnabled = false
                                }
                            }
                        )
                    )
                    
                    if components.keyboardShortcut?.isEnabled == true {
                        keyboardShortcutConfigView
                    }
                }
                
                // Validation hint
                if !components.isValid {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("At least one trigger component must be enabled")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Component Configuration Views
    
    private var modifierKeyConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Modifiers:")
                    .frame(width: 100, alignment: .trailing)
                HStack(spacing: 10) {
                    ModifierToggle(label: "⌘", flag: .command, modifiers: Binding(
                        get: { components.modifierKey?.modifiers ?? [] },
                        set: { components.modifierKey?.modifiers = $0 }
                    ))
                    ModifierToggle(label: "⌃", flag: .control, modifiers: Binding(
                        get: { components.modifierKey?.modifiers ?? [] },
                        set: { components.modifierKey?.modifiers = $0 }
                    ))
                    ModifierToggle(label: "⌥", flag: .option, modifiers: Binding(
                        get: { components.modifierKey?.modifiers ?? [] },
                        set: { components.modifierKey?.modifiers = $0 }
                    ))
                    ModifierToggle(label: "⇧", flag: .shift, modifiers: Binding(
                        get: { components.modifierKey?.modifiers ?? [] },
                        set: { components.modifierKey?.modifiers = $0 }
                    ))
                }
                Spacer()
            }
        }
        .padding(.leading, 20)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var screenZoneConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Zone:")
                    .frame(width: 100, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { components.screenZone?.zone ?? .topRight },
                    set: { components.screenZone?.zone = $0 }
                )) {
                    ForEach(ScreenZone.allCases, id: \.self) { zone in
                        Text(zone.displayName).tag(zone)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                Spacer()
            }
        }
        .padding(.leading, 20)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var dragTypeConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Drag Type:")
                    .frame(width: 100, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { components.dragType?.dragType ?? .leftDrag },
                    set: { components.dragType?.dragType = $0 }
                )) {
                    ForEach(DragModifier.allCases.filter { $0 != .none }, id: \.self) { drag in
                        Text(drag.displayName).tag(drag)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                Spacer()
            }
        }
        .padding(.leading, 20)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var mouseButtonConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Button:")
                    .frame(width: 100, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { components.mouseButton?.button ?? .left },
                    set: { components.mouseButton?.button = $0 }
                )) {
                    ForEach(MouseButtonTrigger.MouseButton.allCases.filter { $0 != .none }, id: \.self) { button in
                        Text(button.rawValue).tag(button)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
            }
        }
        .padding(.leading, 20)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var keyboardShortcutConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcut:")
                    .frame(width: 100, alignment: .trailing)
                KeyboardShortcutFieldView(shortcut: Binding(
                    get: { components.keyboardShortcut?.keyboardTrigger },
                    set: { components.keyboardShortcut?.keyboardTrigger = $0 }
                ))
                .frame(width: 220, height: 28)
                Spacer()
            }
            .padding(.leading, 20)
            
            if components.keyboardShortcut?.isEnabled == true && components.keyboardShortcut?.keyboardTrigger == nil {
                HStack {
                    Spacer().frame(width: 120)
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
    
    // MARK: - Action Section
    
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
                Toggle("Repeat on Hold", isOn: $timing.repeatOnHold)
                if timing.repeatOnHold {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Initial Delay:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $timing.repeatInitialDelay, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", timing.repeatInitialDelay))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                        
                        HStack {
                            Text("Repeat Interval:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $timing.repeatInterval, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", timing.repeatInterval))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
                
                Divider()
                
                Toggle("Long Press Action", isOn: $timing.longPressEnabled)
                if timing.longPressEnabled {
                    HStack {
                        Text("Threshold:")
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $timing.longPressThreshold, in: 0.3...2.0, step: 0.1)
                            .frame(width: 200)
                        Text(String(format: "%.1f s", timing.longPressThreshold))
                            .frame(width: 50, alignment: .trailing)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helper Views
    
    struct ComponentToggleCard: View {
        let icon: String
        let title: String
        let description: String
        @Binding var isEnabled: Bool
        
        var body: some View {
            HStack(spacing: 12) {
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .foregroundColor(isEnabled ? .blue : .secondary)
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isEnabled ? .primary : .secondary)
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(isEnabled ? Color.blue.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }
    
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
    
    // MARK: - Validation & Save
    
    private var isValid: Bool {
        guard components.isValid else { return false }
        guard !selectedActionId.isEmpty else { return false }
        
        // Check required fields for enabled components
        if components.keyboardShortcut?.isEnabled == true && components.keyboardShortcut?.keyboardTrigger == nil {
            return false
        }
        
        return true
    }
    
    private func saveGesture() {
        // Create gesture from components
        let gesture = Gesture(
            components: components,
            actionIdentifier: selectedActionId,
            timing: timing,
            parameters: actionParameters
        )
        
        // Check for conflicts (only if adding or changing trigger)
        if mode == .add || existingGesture?.triggerKey != gesture.triggerKey {
            if uiServices.isGestureConflicting(gesture) {
                conflictMessage = "A gesture with this trigger combination already exists. Each trigger combination can only be assigned one action."
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
