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
    @State private var selectedCategory = "General"
    @State private var hasAdvancedConfig = false
    @State private var advancedConfigCount = 0
    
    enum Mode {
        case add
        case edit
        
        var title: String {
            switch self {
            case .add: return "Add Gesture"
            case .edit: return "Edit Gesture"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }
    }
    
    init(mode: Mode, existingGesture: Gesture? = nil, onSave: @escaping (Gesture) -> Void) {
        self.mode = mode
        self.existingGesture = existingGesture
        self.onSave = onSave
        
        // Initialize state from existing gesture or defaults
        if let gesture = existingGesture {
            _selectedZone = State(initialValue: gesture.zone)
            _selectedModifiers = State(initialValue: gesture.modifiers)
            _selectedDragModifier = State(initialValue: gesture.dragModifier)
            _selectedActionId = State(initialValue: gesture.actionIdentifier)
            _activationType = State(initialValue: gesture.activation.activationType)
            _keyboardShortcut = State(initialValue: gesture.activation.keyboardTrigger)
            _mouseButton = State(initialValue: gesture.activation.mouseButtonTrigger)
            _isEnabled = State(initialValue: gesture.activation.isEnabled)
            _repeatOnHold = State(initialValue: gesture.timing.repeatOnHold)
            _repeatInitialDelay = State(initialValue: gesture.timing.repeatInitialDelay)
            _repeatInterval = State(initialValue: gesture.timing.repeatInterval)
            _longPressEnabled = State(initialValue: gesture.timing.longPressEnabled)
            _longPressThreshold = State(initialValue: gesture.timing.longPressThreshold)
            _actionParameters = State(initialValue: gesture.parameters)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            configurationHeader
            
            Divider()
            
            // Configuration Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    triggerConfigurationSection
                    actionSelectionSection
                    gestureParameterSection
                    activationSettingsSection
                    timingSettingsSection
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            configurationFooter
        }
        .frame(width: 700, height: 650)
        .onAppear {
            updateAdvancedConfigState()
        }
        .alert("Gesture Conflict", isPresented: $showingConflictAlert) {
            Button("OK") {}
        } message: {
            Text(conflictMessage)
        }
    }
    
    // MARK: - View Components
    
    private var configurationHeader: some View {
        HStack {
            Text(mode.title)
                .font(.title2)
                .bold()
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
        }
        .padding()
    }
    
    private var triggerConfigurationSection: some View {
        GroupBox("Trigger") {
            VStack(alignment: .leading, spacing: 12) {
                // Zone Selection
                LabeledContent("Zone:") {
                    Picker("", selection: $selectedZone) {
                        ForEach(ScreenZone.allCases, id: \.self) { zone in
                            Text(zone.displayName).tag(zone)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                // Modifier Keys
                LabeledContent("Modifiers:") {
                    HStack(spacing: 12) {
                        ModifierToggle(label: "⌘", flag: .command, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⌃", flag: .control, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⌥", flag: .option, modifiers: $selectedModifiers)
                        ModifierToggle(label: "⇧", flag: .shift, modifiers: $selectedModifiers)
                    }
                }
                
                // Drag Modifier
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
            .padding(.vertical, 8)
        }
    }
    
    private var actionSelectionSection: some View {
        GroupBox("Action") {
            VStack(alignment: .leading, spacing: 12) {
                // Category Filter
                LabeledContent("Category:") {
                    Picker("", selection: $selectedCategory) {
                        Text("All").tag("All")
                        Text("Core Actions").tag("Core")
                        Text("Window Management").tag("Window")
                        Text("Media Control").tag("Media")
                        Text("System Control").tag("System")
                        Text("Automation").tag("Automation")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                // Action Selection
                LabeledContent("Action:") {
                    Picker("", selection: $selectedActionId) {
                        if selectedActionId.isEmpty {
                            Text("Select an action...").tag("")
                        }
                        ForEach(filteredActions, id: \.0) { actionId, action in
                            Text(action.name)
                                .tag(actionId)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 300)
                }
                
                // Action Description
                if let action = getSelectedAction() {
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var gestureParameterSection: some View {
        Group {
            if let action = getSelectedAction() {
                // Advanced configuration button
                if hasAdvancedConfig {
                    GroupBox("Advanced Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This action requires advanced configuration.")
                                        .font(.system(size: 13))
                                    if advancedConfigCount > 0 {
                                        Text("\(advancedConfigCount) item(s) configured")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Not yet configured")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                Button("Configure...") {
                                    openAdvancedConfiguration(for: action)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Simple parameter fields (skip json params when advanced config handles them)
                let simpleParams = action.supportedParameters.filter { param in
                    if hasAdvancedConfig && param.type == .json { return false }
                    return true
                }
                if !simpleParams.isEmpty {
                    GroupBox("Parameters") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(simpleParams, id: \.key) { paramDef in
                                gestureParamField(for: paramDef)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onChange(of: selectedActionId) { _ in
            initGestureParamDefaults()
            updateAdvancedConfigState()
        }
    }
    
    @ViewBuilder
    private func gestureParamField(for paramDef: ParameterDefinition) -> some View {
        switch paramDef.type {
        case .string, .path, .url:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: gParamString(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        case .number:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: gParamNumber(for: paramDef.key, default: paramDef.defaultValue?.value as? Double ?? 0))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        case .boolean:
            Toggle(paramDef.name, isOn: gParamBool(for: paramDef.key, default: paramDef.defaultValue?.value as? Bool ?? false))
        case .selection:
            if let allowedValues = paramDef.validation?.allowedValues {
                LabeledContent("\(paramDef.name):") {
                    Picker("", selection: gParamString(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? "")) {
                        ForEach(allowedValues.compactMap { $0.value as? String }, id: \.self) { val in
                            Text(val.replacingOccurrences(of: "_", with: " ").capitalized).tag(val)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                }
            }
        case .application:
            LabeledContent("\(paramDef.name):") {
                Picker("", selection: gParamString(for: paramDef.key, default: "")) {
                    Text("Select...").tag("")
                    ForEach(WindowTargeting.getAllRunningApplications(), id: \.bundleId) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 200)
            }
        case .json:
            VStack(alignment: .leading, spacing: 4) {
                Text(paramDef.name)
                    .font(.system(size: 13, weight: .medium))
                Text(paramDef.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: gParamJson(for: paramDef.key))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .script:
            VStack(alignment: .leading, spacing: 4) {
                Text(paramDef.name)
                    .font(.system(size: 13, weight: .medium))
                Text(paramDef.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: gParamString(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .keyboardShortcut:
            LabeledContent("\(paramDef.name):") {
                Text("Configure via Activation settings above")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        default:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: gParamString(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        }
    }
    
    private func gParamJson(for key: String) -> Binding<String> {
        Binding(
            get: {
                if let val = actionParameters[key] {
                    if let dict = val.value as? [String: Any],
                       let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                    if let arr = val.value as? [Any],
                       let data = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                    if let str = val.value as? String {
                        return str
                    }
                }
                return "{}"
            },
            set: { newValue in
                if let data = newValue.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    if let dict = json as? [String: Any] {
                        actionParameters[key] = AnyCodable(dict)
                    } else if let arr = json as? [Any] {
                        actionParameters[key] = AnyCodable(arr)
                    } else {
                        actionParameters[key] = AnyCodable(newValue)
                    }
                } else {
                    actionParameters[key] = AnyCodable(newValue)
                }
            }
        )
    }
    
    private func initGestureParamDefaults() {
        actionParameters.removeAll()
        guard let action = getSelectedAction() else { return }
        for paramDef in action.supportedParameters {
            if let defaultVal = paramDef.defaultValue {
                actionParameters[paramDef.key] = defaultVal
            }
        }
    }
    
    private func gParamString(for key: String, default d: String) -> Binding<String> {
        Binding(get: { actionParameters[key]?.value as? String ?? d }, set: { actionParameters[key] = AnyCodable($0) })
    }
    
    private func gParamNumber(for key: String, default d: Double) -> Binding<String> {
        Binding(
            get: {
                if let v = actionParameters[key]?.value as? Double { return String(v) }
                if let v = actionParameters[key]?.value as? Int { return String(v) }
                return String(d)
            },
            set: { if let v = Double($0) { actionParameters[key] = AnyCodable(v) } }
        )
    }
    
    private func gParamBool(for key: String, default d: Bool) -> Binding<Bool> {
        Binding(get: { actionParameters[key]?.value as? Bool ?? d }, set: { actionParameters[key] = AnyCodable($0) })
    }
    
    private var activationSettingsSection: some View {
        GroupBox("Activation") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enabled", isOn: $isEnabled)
                
                LabeledContent("Activation Type:") {
                    Picker("", selection: $activationType) {
                        ForEach(ActivationSettings.ActivationType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                // Keyboard Shortcut (if applicable)
                if shouldShowKeyboardShortcut {
                    LabeledContent("Keyboard Shortcut:") {
                        KeyboardShortcutFieldView(shortcut: $keyboardShortcut)
                            .frame(width: 200, height: 24)
                    }
                }
                
                // Mouse Button (if applicable)
                if shouldShowMouseButton {
                    LabeledContent("Mouse Button:") {
                        mouseButtonPicker
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var timingSettingsSection: some View {
        GroupBox("Timing (Optional)") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Repeat on Hold", isOn: $repeatOnHold)
                
                if repeatOnHold {
                    repeatDelayControls
                }
                
                Toggle("Long Press Action", isOn: $longPressEnabled)
                
                if longPressEnabled {
                    longPressControls
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var repeatDelayControls: some View {
        Group {
            LabeledContent("Initial Delay:") {
                HStack {
                    Slider(value: $repeatInitialDelay, in: 0.1...2.0, step: 0.1)
                        .frame(width: 150)
                    Text(String(format: "%.1f s", repeatInitialDelay))
                        .frame(width: 50, alignment: .trailing)
                }
            }
            
            LabeledContent("Repeat Interval:") {
                HStack {
                    Slider(value: $repeatInterval, in: 0.1...2.0, step: 0.1)
                        .frame(width: 150)
                    Text(String(format: "%.1f s", repeatInterval))
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
    
    private var longPressControls: some View {
        LabeledContent("Long Press Threshold:") {
            HStack {
                Slider(value: $longPressThreshold, in: 0.3...2.0, step: 0.1)
                    .frame(width: 150)
                Text(String(format: "%.1f s", longPressThreshold))
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
    
    private var mouseButtonPicker: some View {
        Picker("", selection: Binding<MouseButtonTrigger.MouseButton>(
            get: { mouseButton?.button ?? .left },
            set: { newButton in
                if mouseButton != nil {
                    mouseButton?.button = newButton
                } else {
                    mouseButton = MouseButtonTrigger(button: newButton, modifiers: [])
                }
            }
        )) {
            Text("Left").tag(MouseButtonTrigger.MouseButton.left)
            Text("Right").tag(MouseButtonTrigger.MouseButton.right)
            Text("Middle").tag(MouseButtonTrigger.MouseButton.middle)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }
    
    private func updateAdvancedConfigState() {
        guard let (plugin, action) = PluginManager.shared.getAction(identifier: selectedActionId) else {
            hasAdvancedConfig = false
            advancedConfigCount = 0
            return
        }
        hasAdvancedConfig = plugin.hasAdvancedConfiguration(for: action)
        updateAdvancedConfigCount()
    }
    
    private func updateAdvancedConfigCount() {
        if let bundleData = actionParameters["bundle_actions"] {
            if let array = bundleData.value as? [[String: Any]] {
                advancedConfigCount = array.count
            } else if let jsonStr = bundleData.value as? String,
                      let data = jsonStr.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                advancedConfigCount = arr.count
            } else {
                advancedConfigCount = 0
            }
        } else {
            advancedConfigCount = 0
        }
    }
    
    private func openAdvancedConfiguration(for action: PluginAction) {
        guard let (plugin, _) = PluginManager.shared.getAction(identifier: selectedActionId),
              let window = NSApp.keyWindow else { return }
        
        plugin.presentAdvancedConfiguration(
            for: action,
            currentParameters: actionParameters,
            parentWindow: window
        ) { updatedParams in
            if let updatedParams = updatedParams {
                DispatchQueue.main.async {
                    self.actionParameters = updatedParams
                    self.updateAdvancedConfigCount()
                }
            }
        }
    }
    
    private var configurationFooter: some View {
        HStack {
            // Preview
            VStack(alignment: .leading) {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(gesturePreviewText)
                    .font(.system(.body, design: .monospaced))
            }
            
            Spacer()
            
            Button(mode.buttonTitle) {
                saveGesture()
            }
            .keyboardShortcut(.return)
            .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Computed Properties for Conditional Display
    
    private var shouldShowKeyboardShortcut: Bool {
        activationType == .keyboard || 
        activationType == .both || 
        activationType == .keyboardMouseButton || 
        activationType == .all
    }
    
    private var shouldShowMouseButton: Bool {
        activationType == .mouseButton || 
        activationType == .gestureMouseButton || 
        activationType == .keyboardMouseButton || 
        activationType == .all
    }
    
    // MARK: - Helper Views
    
    struct ModifierToggle: View {
        let label: String
        let flag: NSEvent.ModifierFlags
        @Binding var modifiers: NSEvent.ModifierFlags
        
        var body: some View {
            Toggle(isOn: Binding(
                get: { modifiers.contains(flag) },
                set: { enabled in
                    if enabled {
                        modifiers.insert(flag)
                    } else {
                        modifiers.remove(flag)
                    }
                }
            )) {
                Text(label)
            }
            .toggleStyle(.button)
        }
    }
    
    // MARK: - Helper Methods
    
    private var filteredActions: [(String, PluginAction)] {
        let allActions = PluginManager.shared.getAllActions()
        
        if selectedCategory == "All" {
            return allActions.map { ($0.pluginId + "." + $0.action.id, $0.action) }
        }
        
        // Filter by category (plugin prefix)
        let prefix = selectedCategory.lowercased()
        return allActions
            .filter { $0.pluginId.lowercased().contains(prefix) }
            .map { ($0.pluginId + "." + $0.action.id, $0.action) }
    }
    
    private func getSelectedAction() -> PluginAction? {
        return PluginManager.shared.getAction(identifier: selectedActionId)?.action
    }
    
    private var gesturePreviewText: String {
        var parts: [String] = []
        
        // Zone
        parts.append(selectedZone.displayName)
        
        // Modifiers
        var modParts: [String] = []
        if selectedModifiers.contains(.command) { modParts.append("⌘") }
        if selectedModifiers.contains(.control) { modParts.append("⌃") }
        if selectedModifiers.contains(.option) { modParts.append("⌥") }
        if selectedModifiers.contains(.shift) { modParts.append("⇧") }
        if !modParts.isEmpty {
            parts.append("+")
            parts.append(modParts.joined())
        }
        
        // Drag
        if selectedDragModifier != .none {
            parts.append("+")
            parts.append(selectedDragModifier.displayName)
        }
        
        // Action
        if let action = getSelectedAction() {
            parts.append("→")
            parts.append(action.name)
        }
        
        return parts.joined(separator: " ")
    }
    
    private var isValid: Bool {
        // Must have an action selected
        guard !selectedActionId.isEmpty else { return false }
        
        // Must have at least gesture, keyboard, or mouse button enabled
        switch activationType {
        case .keyboard, .keyboardMouseButton:
            guard keyboardShortcut != nil else { return false }
        case .mouseButton, .gestureMouseButton:
            guard mouseButton != nil else { return false }
        default:
            break
        }
        
        return true
    }
    
    private func saveGesture() {
        // Create the new/updated gesture
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
        
        // Check for conflicts (except when editing the same gesture)
        if mode == .add || existingGesture?.id != gesture.id {
            if uiServices.isGestureConflicting(gesture) {
                conflictMessage = "A gesture with this combination of zone, modifiers, and drag already exists."
                showingConflictAlert = true
                return
            }
        }
        
        // Save the gesture
        onSave(gesture)
        dismiss()
    }
}

// MARK: - KeyboardShortcutFieldView (SwiftUI Wrapper)

struct KeyboardShortcutFieldView: NSViewRepresentable {
    @Binding var shortcut: KeyboardTrigger?
    
    func makeNSView(context: Context) -> KeyboardShortcutField {
        let field = KeyboardShortcutField()
        field.onShortcutCapture = { capturedShortcut in
            // Convert KeyboardShortcut to KeyboardTrigger
            // Convert CGEventFlags to NSEvent.ModifierFlags
            var modifierFlags = NSEvent.ModifierFlags()
            if capturedShortcut.modifiers.contains(.maskCommand) {
                modifierFlags.insert(.command)
            }
            if capturedShortcut.modifiers.contains(.maskControl) {
                modifierFlags.insert(.control)
            }
            if capturedShortcut.modifiers.contains(.maskAlternate) {
                modifierFlags.insert(.option)
            }
            if capturedShortcut.modifiers.contains(.maskShift) {
                modifierFlags.insert(.shift)
            }
            
            shortcut = KeyboardTrigger(
                keyCode: capturedShortcut.keyCode,
                modifiers: modifierFlags,
                displayString: capturedShortcut.displayString
            )
        }
        return field
    }
    
    func updateNSView(_ nsView: KeyboardShortcutField, context: Context) {
        // Update the field's display if the shortcut changes externally
        if let trigger = shortcut {
            // Convert NSEvent.ModifierFlags to CGEventFlags
            var cgFlags = CGEventFlags(rawValue: 0)
            if trigger.modifiers.contains(.command) {
                cgFlags.insert(.maskCommand)
            }
            if trigger.modifiers.contains(.control) {
                cgFlags.insert(.maskControl)
            }
            if trigger.modifiers.contains(.option) {
                cgFlags.insert(.maskAlternate)
            }
            if trigger.modifiers.contains(.shift) {
                cgFlags.insert(.maskShift)
            }
            
            nsView.capturedShortcut = KeyboardShortcut(
                keyCode: trigger.keyCode,
                modifiers: cgFlags,
                displayString: trigger.displayString
            )
            nsView.stringValue = trigger.displayString
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
        GestureConfigurationSheet(
            mode: .add,
            onSave: { gesture in
                _ = uiServices.addGesture(gesture)
            }
        )
    }
}

struct EditGestureSheet: View {
    let gesture: Gesture
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        GestureConfigurationSheet(
            mode: .edit,
            existingGesture: gesture,
            onSave: { updatedGesture in
                _ = uiServices.updateGesture(oldGesture: gesture, newGesture: updatedGesture)
            }
        )
    }
}
