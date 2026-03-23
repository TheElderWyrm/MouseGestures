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
    @State private var gestureName: String
    
    // UI State
    @State private var showingConflictAlert = false
    @State private var conflictMessage = ""
    @State private var pendingGesture: Gesture?
    
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
            _components = State(initialValue: g.components)
            _selectedActionId = State(initialValue: g.actionIdentifier)
            _actionParameters = State(initialValue: g.parameters)
            _timing = State(initialValue: g.timing)
            _isEnabled = State(initialValue: g.isEnabled)
            _gestureName = State(initialValue: g.name ?? "")
        } else {
            var defaultComponents = GestureActivationComponents()
            defaultComponents.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: [.command, .control])
            defaultComponents.screenZone = ScreenZoneConfig(isEnabled: true, zone: .topRight)
            _components = State(initialValue: defaultComponents)
            _selectedActionId = State(initialValue: "")
            _actionParameters = State(initialValue: [:])
            _timing = State(initialValue: TimingSettings())
            _isEnabled = State(initialValue: true)
            _gestureName = State(initialValue: "")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader(mode.title)
            
            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    // Name + Enable toggle
                    HStack(spacing: MGStyle.Spacing.lg) {
                        Toggle("Enabled", isOn: $isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        TextField("Custom name (optional)", text: $gestureName)
                            .textFieldStyle(.roundedBorder)
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
            Button("Cancel", role: .cancel) { pendingGesture = nil }
            Button("Replace", role: .destructive) { replaceConflictingGesture() }
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
    
    // MARK: - Detection Plugin Availability

    private func isPluginEnabled(_ id: String) -> Bool {
        DetectionPluginManager.shared.getAllPlugins().first { $0.identifier == id }?.isEnabled ?? true
    }

    // MARK: - Activation Components Section

    private var activationComponentsSection: some View {
        GroupBox("Trigger Configuration") {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                VStack(spacing: MGStyle.Spacing.sm) {
                    // Modifier Keys Component
                    if isPluginEnabled(ModifierKeyDetectorPlugin.pluginIdentifier) {
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
                    } // end modifier plugin guard

                    // Screen Zone Component
                    if isPluginEnabled(ScreenZoneDetectorPlugin.pluginIdentifier) {
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
                    } // end screenzone plugin guard

                    // Mouse Input Component (combines Drag Type + Mouse Button)
                    if isPluginEnabled(MouseButtonDetectorPlugin.pluginIdentifier) {
                    ComponentToggleCard(
                        icon: "computermouse",
                        title: "Mouse Input",
                        description: "Activate with a click or drag gesture",
                        isEnabled: Binding(
                            get: { (components.dragType?.isEnabled ?? false) || (components.mouseButton?.isEnabled ?? false) },
                            set: { enabled in
                                if enabled {
                                    // Default: left drag (most common)
                                    if components.dragType == nil { components.dragType = DragTypeConfig(isEnabled: false, dragType: .leftDrag) }
                                    if components.mouseButton == nil { components.mouseButton = MouseButtonConfig(isEnabled: false, button: .left) }
                                    components.dragType?.isEnabled = true
                                    components.mouseButton?.isEnabled = false
                                } else {
                                    components.dragType?.isEnabled = false
                                    components.mouseButton?.isEnabled = false
                                }
                            }
                        )
                    )

                    if (components.dragType?.isEnabled ?? false) || (components.mouseButton?.isEnabled ?? false) {
                        mouseInputConfigView
                    }
                    } // end mouse plugin guard

                    // Keyboard Shortcut Component
                    if isPluginEnabled(KeyboardShortcutDetectorPlugin.pluginIdentifier) {
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
                    } // end keyboard plugin guard
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
        HStack {
            Text("Keys:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            HStack(spacing: MGStyle.Spacing.sm) {
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
            Spacer()
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
            .frame(width: 180)
            .labelsHidden()
            Spacer()
        }
        .padding(.leading, MGStyle.Spacing.xxl)
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
        .cornerRadius(MGStyle.Corner.md)
    }

    // MARK: Unified Mouse Input (replaces separate Drag + Button sections)

    private enum MouseInputType: Equatable {
        case anyDrag, leftDrag, rightDrag, middleDrag
        case anyClick, leftClick, rightClick, middleClick
        var displayName: String {
            switch self {
            case .anyDrag:   return "Any Drag"
            case .leftDrag:  return "Left Drag"
            case .rightDrag: return "Right Drag"
            case .middleDrag: return "Middle Drag"
            case .anyClick:  return "Any Click"
            case .leftClick: return "Left Click"
            case .rightClick: return "Right Click"
            case .middleClick: return "Middle Click"
            }
        }
    }

    private func currentMouseInputType() -> MouseInputType {
        if let drag = components.dragType, drag.isEnabled {
            switch drag.dragType {
            case .anyDrag:   return .anyDrag
            case .leftDrag:  return .leftDrag
            case .rightDrag: return .rightDrag
            case .middleDrag: return .middleDrag
            default:         return .leftDrag
            }
        }
        if let btn = components.mouseButton, btn.isEnabled {
            switch btn.button {
            case .any:    return .anyClick
            case .right:  return .rightClick
            case .middle: return .middleClick
            default:      return .leftClick
            }
        }
        return .leftDrag
    }

    private func applyMouseInputType(_ type: MouseInputType) {
        switch type {
        case .anyDrag:
            components.dragType = DragTypeConfig(isEnabled: true, dragType: .anyDrag)
            components.mouseButton?.isEnabled = false
        case .leftDrag:
            components.dragType = DragTypeConfig(isEnabled: true, dragType: .leftDrag)
            components.mouseButton?.isEnabled = false
        case .rightDrag:
            components.dragType = DragTypeConfig(isEnabled: true, dragType: .rightDrag)
            components.mouseButton?.isEnabled = false
        case .middleDrag:
            components.dragType = DragTypeConfig(isEnabled: true, dragType: .middleDrag)
            components.mouseButton?.isEnabled = false
        case .anyClick:
            components.dragType?.isEnabled = false
            components.mouseButton = MouseButtonConfig(isEnabled: true, button: .any)
        case .leftClick:
            components.dragType?.isEnabled = false
            components.mouseButton = MouseButtonConfig(isEnabled: true, button: .left)
        case .rightClick:
            components.dragType?.isEnabled = false
            components.mouseButton = MouseButtonConfig(isEnabled: true, button: .right)
        case .middleClick:
            components.dragType?.isEnabled = false
            components.mouseButton = MouseButtonConfig(isEnabled: true, button: .middle)
        }
    }

    private var mouseInputConfigView: some View {
        HStack {
            Text("Type:")
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Picker("", selection: Binding(
                get: { currentMouseInputType() },
                set: { applyMouseInputType($0) }
            )) {
                Group {
                    Text("Any Drag").tag(MouseInputType.anyDrag)
                    Text("Left Drag").tag(MouseInputType.leftDrag)
                    Text("Right Drag").tag(MouseInputType.rightDrag)
                    Text("Middle Drag").tag(MouseInputType.middleDrag)
                    Divider()
                    Text("Any Click").tag(MouseInputType.anyClick)
                    Text("Left Click").tag(MouseInputType.leftClick)
                    Text("Right Click").tag(MouseInputType.rightClick)
                    Text("Middle Click").tag(MouseInputType.middleClick)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
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
            .frame(width: 180)
            .labelsHidden()
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
            .frame(width: 180)
            .labelsHidden()
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
            .frame(width: 180, height: 24)

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
                HStack(spacing: MGStyle.Spacing.xs) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    if !name.isEmpty {
                        Text(name)
                            .font(.system(size: MGStyle.FontSize.caption, weight: .medium))
                    }
                }
                .padding(.horizontal, MGStyle.Spacing.md)
                .padding(.vertical, MGStyle.Spacing.sm)
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
        // Build a gesture that syncs component trigger data (keyboard shortcut,
        // mouse button) into genericActivation so detection plugins can find it.
        var activation = GenericActivation(isEnabled: isEnabled)
        if components.keyboardShortcut?.isEnabled == true {
            activation.setKeyboardTrigger(components.keyboardShortcut?.keyboardTrigger)
        }
        if components.mouseButton?.isEnabled == true,
           let button = components.mouseButton?.button, button != .none {
            activation.setMouseButtonTrigger(MouseButtonTrigger(button: button, modifiers: []))
        }

        var gesture = Gesture(
            components: components,
            genericActivation: activation,
            actionIdentifier: selectedActionId,
            timing: timing,
            parameters: actionParameters
        )
        gesture.name = gestureName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gestureName.trimmingCharacters(in: .whitespaces)
        
        if mode == .add || existingGesture?.triggerKey != gesture.triggerKey {
            if uiServices.isGestureConflicting(gesture) {
                conflictMessage = "A gesture with this trigger combination already exists. Replace the existing gesture?"
                pendingGesture = gesture
                showingConflictAlert = true
                return
            }
        }

        onSave(gesture)
        dismiss()
    }

    private func replaceConflictingGesture() {
        guard let gesture = pendingGesture else { return }
        pendingGesture = nil
        // Remove the conflicting gesture, then save the new one
        if let conflicting = uiServices.gestures.first(where: { $0.triggerKey == gesture.triggerKey }) {
            _ = uiServices.removeGesture(conflicting)
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
