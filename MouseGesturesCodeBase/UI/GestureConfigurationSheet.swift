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
            _components = State(initialValue: g.components)
            _selectedActionId = State(initialValue: g.actionIdentifier)
            _actionParameters = State(initialValue: g.parameters)
            _timing = State(initialValue: g.timing)
            _isEnabled = State(initialValue: g.isEnabled)
        } else {
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
            MGSheetHeader(mode.title)
            
            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    // Enable toggle
                    HStack {
                        Toggle("Enabled", isOn: $isEnabled)
                            .toggleStyle(.switch)
                        Spacer()
                    }
                    
                    activationComponentsSection
                    actionSection
                    timingSettingsSection
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter(mode.buttonTitle, disabled: !isValid, action: {
                saveGesture()
            }, cancel: { dismiss() }) {
                // Gesture preview inline in footer
                Text(gesturePreviewText)
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: 750, height: 700)
        .alert("Gesture Conflict", isPresented: $showingConflictAlert) {
            Button("OK") {}
        } message: {
            Text(conflictMessage)
        }
    }
    
    // MARK: - Gesture Preview Text
    
    private var gesturePreviewText: String {
        var triggerParts: [String] = []
        
        if components.screenZone?.isEnabled == true {
            triggerParts.append(components.screenZone?.zone.displayName ?? "Zone")
        }
        if components.modifierKey?.isEnabled == true {
            let mods = components.modifierKey?.modifiers ?? []
            let modStr = mods.symbolString
            if !modStr.isEmpty { triggerParts.append(modStr) }
        }
        if components.dragType?.isEnabled == true {
            triggerParts.append(components.dragType?.dragType.displayName ?? "Drag")
        }
        if components.mouseButton?.isEnabled == true {
            triggerParts.append(components.mouseButton?.button.rawValue ?? "Click")
        }
        if components.keyboardShortcut?.isEnabled == true {
            triggerParts.append(components.keyboardShortcut?.keyboardTrigger?.displayString ?? "Key")
        }
        
        let trigger = triggerParts.isEmpty ? "No trigger" : triggerParts.joined(separator: " + ")
        
        let actionName: String
        if let action = PluginManager.shared.getAction(identifier: selectedActionId)?.action {
            actionName = action.name
        } else if !selectedActionId.isEmpty {
            actionName = selectedActionId
        } else {
            actionName = "No action"
        }
        
        return "\(trigger) \u{2192} \(actionName)"
    }
    
    // MARK: - Activation Components Section
    
    private var activationComponentsSection: some View {
        GroupBox("Trigger Configuration") {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                VStack(spacing: MGStyle.Spacing.sm) {
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
                    .padding(.top, MGStyle.Spacing.sm)
                }
            }
            .padding(.vertical, MGStyle.Spacing.md)
        }
    }
    
    // MARK: - Component Configuration Views
    
    private var modifierKeyConfigView: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            HStack(spacing: MGStyle.Spacing.lg) {
                ModifierToggle(label: "⌘", name: "Command", flag: .command, modifiers: Binding(
                    get: { components.modifierKey?.modifiers ?? [] },
                    set: { components.modifierKey?.modifiers = $0 }
                ))
                ModifierToggle(label: "⌃", name: "Control", flag: .control, modifiers: Binding(
                    get: { components.modifierKey?.modifiers ?? [] },
                    set: { components.modifierKey?.modifiers = $0 }
                ))
                ModifierToggle(label: "⌥", name: "Option", flag: .option, modifiers: Binding(
                    get: { components.modifierKey?.modifiers ?? [] },
                    set: { components.modifierKey?.modifiers = $0 }
                ))
                ModifierToggle(label: "⇧", name: "Shift", flag: .shift, modifiers: Binding(
                    get: { components.modifierKey?.modifiers ?? [] },
                    set: { components.modifierKey?.modifiers = $0 }
                ))
            }
            
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
    }
    
    private var screenZoneConfigView: some View {
        HStack {
            Text("Zone:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Picker("", selection: Binding(
                get: { components.screenZone?.zone ?? .topRight },
                set: { components.screenZone?.zone = $0 }
            )) {
                ForEach(ScreenZone.allCases, id: \.self) { zone in
                    Text(zone.displayName).tag(zone)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .labelsHidden()
            Spacer()
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
    }
    
    private var dragTypeConfigView: some View {
        HStack {
            Text("Drag Type:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Picker("", selection: Binding(
                get: { components.dragType?.dragType ?? .leftDrag },
                set: { components.dragType?.dragType = $0 }
            )) {
                ForEach(DragModifier.allCases.filter { $0 != .none }, id: \.self) { drag in
                    Text(drag.displayName).tag(drag)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            Spacer()
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
    }
    
    private var mouseButtonConfigView: some View {
        HStack {
            Text("Button:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Picker("", selection: Binding(
                get: { components.mouseButton?.button ?? .left },
                set: { components.mouseButton?.button = $0 }
            )) {
                ForEach(MouseButtonTrigger.MouseButton.allCases, id: \.self) { button in
                    Text(button.rawValue).tag(button)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            Spacer()
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
    }
    
    private var keyboardShortcutConfigView: some View {
        HStack {
            Text("Shortcut:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            KeyboardShortcutFieldView(shortcut: Binding(
                get: { components.keyboardShortcut?.keyboardTrigger },
                set: { components.keyboardShortcut?.keyboardTrigger = $0 }
            ))
            .frame(width: 200, height: 24)
            
            if components.keyboardShortcut?.isEnabled == true && components.keyboardShortcut?.keyboardTrigger == nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                Text("Required")
                    .font(.system(size: MGStyle.FontSize.badge))
                    .foregroundColor(.orange)
            }
            Spacer()
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
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
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Toggle("Repeat on Hold", isOn: $timing.repeatOnHold)
                if timing.repeatOnHold {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                        HStack {
                            Text("Initial Delay:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $timing.repeatInitialDelay, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", timing.repeatInitialDelay))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, MGStyle.Spacing.xxl)
                        
                        HStack {
                            Text("Repeat Interval:")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $timing.repeatInterval, in: 0.1...2.0, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f s", timing.repeatInterval))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, MGStyle.Spacing.xxl)
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
                    .padding(.leading, MGStyle.Spacing.xxl)
                }
            }
            .padding(.vertical, MGStyle.Spacing.md)
        }
    }
    
    // MARK: - Helper Views
    
    struct ComponentToggleCard: View {
        let icon: String
        let title: String
        let description: String
        @Binding var isEnabled: Bool
        
        var body: some View {
            HStack(spacing: MGStyle.Spacing.md) {
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isEnabled ? .blue : .secondary)
                    .frame(width: 14)
                
                Text(title)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Spacer()
                
                Text(description)
                    .font(.system(size: MGStyle.FontSize.badge))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, MGStyle.Spacing.lg)
            .padding(.vertical, MGStyle.Spacing.md)
            .background(isEnabled ? Color.blue.opacity(0.06) : Color.clear)
            .cornerRadius(MGStyle.Corner.md)
        }
    }
    
    struct ModifierToggle: View {
        let label: String
        let name: String
        let flag: NSEvent.ModifierFlags
        @Binding var modifiers: NSEvent.ModifierFlags
        
        init(label: String, name: String = "", flag: NSEvent.ModifierFlags, modifiers: Binding<NSEvent.ModifierFlags>) {
            self.label = label
            self.name = name
            self.flag = flag
            self._modifiers = modifiers
        }
        
        private var isActive: Bool { modifiers.contains(flag) }
        
        var body: some View {
            Button(action: {
                if isActive { modifiers.remove(flag) } else { modifiers.insert(flag) }
            }) {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 18, weight: .semibold))
                    if !name.isEmpty {
                        Text(name)
                            .font(.system(size: 9))
                    }
                }
                .frame(width: 64, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                        .fill(isActive ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                        .stroke(isActive ? Color.accentColor : MGStyle.Colors.separator, lineWidth: isActive ? 1.5 : 0.5)
                )
                .foregroundColor(isActive ? .white : .primary)
            }
            .buttonStyle(.plain)
            .help(name)
        }
    }
    
    // MARK: - Validation & Save
    
    private var isValid: Bool {
        guard components.isValid else { return false }
        guard !selectedActionId.isEmpty else { return false }
        if components.keyboardShortcut?.isEnabled == true && components.keyboardShortcut?.keyboardTrigger == nil {
            return false
        }
        return true
    }
    
    private func saveGesture() {
        let gesture = Gesture(
            components: components,
            actionIdentifier: selectedActionId,
            timing: timing,
            parameters: actionParameters
        )
        
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
