import SwiftUI

// MARK: - Plugin Settings View

/// A SwiftUI view that dynamically renders all detection plugin settings
struct PluginSettingsView: View {
    @State private var showAdvanced = false
    @State private var selectedCategory: PluginSettingDefinition.SettingCategory = .detection
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Detection Plugin Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Toggle("Show Advanced", isOn: $showAdvanced)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            // Category Picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(PluginSettingDefinition.SettingCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            
            // Settings for selected category
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(getSettingsForCategory(selectedCategory), id: \.definition.key) { item in
                        if shouldShowSetting(item.definition) {
                            PluginSettingRow(
                                plugin: item.plugin,
                                definition: item.definition,
                                refreshTrigger: $refreshTrigger
                            )
                        }
                    }
                    
                    if getSettingsForCategory(selectedCategory).isEmpty {
                        Text("No settings available for this category")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
        .id(refreshTrigger)
    }
    
    private func getSettingsForCategory(_ category: PluginSettingDefinition.SettingCategory) -> [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] {
        let allSettings = DetectionPluginManager.shared.getAllSettingsDefinitions()
        return allSettings[category] ?? []
    }
    
    private func shouldShowSetting(_ definition: PluginSettingDefinition) -> Bool {
        if definition.isAdvanced && !showAdvanced {
            return false
        }
        return true
    }
}

// MARK: - Plugin Setting Row

struct PluginSettingRow: View {
    let plugin: DetectionPlugin
    let definition: PluginSettingDefinition
    @Binding var refreshTrigger: UUID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Check if setting should be visible based on dependencies
            if isSettingVisible() {
                settingControl
                    .disabled(!plugin.isEnabled)
                    .opacity(plugin.isEnabled ? 1.0 : 0.5)
            }
        }
    }
    
    private func isSettingVisible() -> Bool {
        return plugin.settings.isSettingVisible(definition.key)
    }
    
    @ViewBuilder
    private var settingControl: some View {
        switch definition.type {
        case .toggle(let label):
            toggleControl(label: label)
            
        case .slider(let min, let max, let step, let unit):
            sliderControl(min: min, max: max, step: step, unit: unit)
            
        case .stepper(let min, let max, let step):
            stepperControl(min: min, max: max, step: step)
            
        case .picker(let options):
            pickerControl(options: options)
            
        case .segmentedPicker(let options):
            segmentedPickerControl(options: options)
            
        case .color:
            colorControl()
            
        case .text(let placeholder, let maxLength):
            textControl(placeholder: placeholder, maxLength: maxLength)
            
        case .button(let title, let style, let action):
            buttonControl(title: title, style: style, action: action)
            
        case .info(let text):
            infoControl(text: text)
            
        default:
            Text("Unsupported setting type")
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Toggle Control
    
    private func toggleControl(label: String) -> some View {
        Toggle(isOn: Binding(
            get: { plugin.settings.getBool(definition.key, default: definition.defaultValue as? Bool ?? false) },
            set: { newValue in
                updateSetting(value: newValue)
            }
        )) {
            settingLabel
        }
    }
    
    // MARK: - Slider Control
    
    private func sliderControl(min: Double, max: Double, step: Double, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                settingLabel
                Spacer()
                Text(formatValue(plugin.settings.getDouble(definition.key, default: definition.defaultValue as? Double ?? min), unit: unit))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Slider(
                value: Binding(
                    get: { plugin.settings.getDouble(definition.key, default: definition.defaultValue as? Double ?? min) },
                    set: { newValue in
                        updateSetting(value: newValue)
                    }
                ),
                in: min...max,
                step: step
            )
        }
    }
    
    // MARK: - Stepper Control
    
    private func stepperControl(min: Int, max: Int, step: Int) -> some View {
        HStack {
            settingLabel
            Spacer()
            Stepper(
                value: Binding(
                    get: { plugin.settings.getInt(definition.key, default: definition.defaultValue as? Int ?? min) },
                    set: { newValue in
                        updateSetting(value: newValue)
                    }
                ),
                in: min...max,
                step: step
            ) {
                Text("\(plugin.settings.getInt(definition.key, default: definition.defaultValue as? Int ?? min))")
                    .font(.system(size: 13, design: .monospaced))
            }
        }
    }
    
    // MARK: - Picker Control
    
    private func pickerControl(options: [PluginSettingDefinition.PickerOption]) -> some View {
        HStack {
            settingLabel
            Spacer()
            Picker("", selection: Binding(
                get: { plugin.settings.getString(definition.key, default: definition.defaultValue as? String ?? "") },
                set: { newValue in
                    updateSetting(value: newValue)
                }
            )) {
                ForEach(options, id: \.value) { option in
                    Text(option.displayName).tag(option.value)
                }
            }
            .frame(width: 200)
        }
    }
    
    // MARK: - Segmented Picker Control
    
    private func segmentedPickerControl(options: [PluginSettingDefinition.PickerOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingLabel
            Picker("", selection: Binding(
                get: { plugin.settings.getString(definition.key, default: definition.defaultValue as? String ?? "") },
                set: { newValue in
                    updateSetting(value: newValue)
                }
            )) {
                ForEach(options, id: \.value) { option in
                    Text(option.displayName).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    // MARK: - Color Control
    
    private func colorControl() -> some View {
        HStack {
            settingLabel
            Spacer()
            ColorPicker("", selection: Binding(
                get: {
                    let nsColor = plugin.settings.getColor(definition.key, default: definition.defaultValue as? NSColor ?? .white)
                    return Color(nsColor)
                },
                set: { newValue in
                    updateSetting(value: NSColor(newValue))
                }
            ))
            .labelsHidden()
        }
    }
    
    // MARK: - Text Control
    
    private func textControl(placeholder: String?, maxLength: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingLabel
            TextField(
                placeholder ?? "",
                text: Binding(
                    get: { plugin.settings.getString(definition.key, default: definition.defaultValue as? String ?? "") },
                    set: { newValue in
                        var value = newValue
                        if let max = maxLength, value.count > max {
                            value = String(value.prefix(max))
                        }
                        updateSetting(value: value)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
    }
    
    // MARK: - Button Control
    
    private func buttonControl(title: String, style: PluginSettingDefinition.SettingType.ButtonStyle, action: @escaping () -> Void) -> some View {
        HStack {
            if let description = definition.description {
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(definition.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            
            Spacer()
            
            buttonForStyle(title: title, style: style, action: action)
        }
    }
    
    @ViewBuilder
    private func buttonForStyle(title: String, style: PluginSettingDefinition.SettingType.ButtonStyle, action: @escaping () -> Void) -> some View {
        switch style {
        case .destructive:
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .primary:
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        case .normal:
            Button(title, action: action)
                .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Info Control
    
    private func infoControl(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Setting Label
    
    private var settingLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(definition.displayName)
                    .font(.system(size: 13, weight: .medium))
                
                if definition.isAdvanced {
                    Text("Advanced")
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(3)
                }
            }
            
            if let description = definition.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show plugin name for clarity
            Text("Plugin: \(plugin.name)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    // MARK: - Helpers
    
    private func formatValue(_ value: Double, unit: String?) -> String {
        let formatted: String
        if value == floor(value) {
            formatted = String(format: "%.0f", value)
        } else {
            formatted = String(format: "%.1f", value)
        }
        
        if let unit = unit {
            return "\(formatted) \(unit)"
        }
        return formatted
    }
    
    private func updateSetting(value: Any) {
        DetectionPluginManager.shared.updatePluginSetting(plugin.identifier, key: definition.key, value: value)
        
        // Trigger refresh to update dependent settings visibility
        DispatchQueue.main.async {
            refreshTrigger = UUID()
        }
    }
}

// MARK: - Compact Plugin Settings Section

/// A more compact view for embedding in existing settings views
struct CompactPluginSettingsSection: View {
    let category: PluginSettingDefinition.SettingCategory
    let showAdvanced: Bool
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(getSettingsForCategory(), id: \.definition.key) { item in
                if shouldShowSetting(item.definition) {
                    PluginSettingRow(
                        plugin: item.plugin,
                        definition: item.definition,
                        refreshTrigger: $refreshTrigger
                    )
                    
                    if item.definition.key != getSettingsForCategory().last?.definition.key {
                        Divider()
                    }
                }
            }
        }
        .id(refreshTrigger)
    }
    
    private func getSettingsForCategory() -> [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] {
        let allSettings = DetectionPluginManager.shared.getAllSettingsDefinitions()
        return allSettings[category] ?? []
    }
    
    private func shouldShowSetting(_ definition: PluginSettingDefinition) -> Bool {
        if definition.isAdvanced && !showAdvanced {
            return false
        }
        return true
    }
}

// MARK: - Preview

#if DEBUG
struct PluginSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PluginSettingsView()
            .frame(width: 600, height: 500)
    }
}
#endif
