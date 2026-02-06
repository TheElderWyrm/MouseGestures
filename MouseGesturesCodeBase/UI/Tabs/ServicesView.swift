import SwiftUI

// MARK: - Services View
/// UI for managing service plugins
struct ServicesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var servicePlugins: [ServicePluginInfo] = []
    @State private var selectedCategory: ServiceCategory?
    @State private var searchText = ""
    
    // Sheet presentation - using single enum to avoid multiple .sheet modifier bug
    enum ActiveSheet: Identifiable {
        case configure(ServicePluginInfo)
        case install
        
        var id: String {
            switch self {
            case .configure(let plugin): return "configure-\(plugin.id)"
            case .install: return "install"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    private let pluginManager = ServicePluginManager.shared
    
    var body: some View {
        HSplitView {
            // Categories sidebar
            categorySidebar
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // Services list
            servicesContent
                .frame(minWidth: 400)
        }
        .onAppear {
            loadServicePlugins()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .configure(let plugin):
                ServiceConfigurationSheet(plugin: plugin)
            case .install:
                ServiceInstallSheet { url in
                    installPlugin(from: url)
                }
            }
        }
    }
    
    // MARK: - Category Sidebar
    
    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Categories")
                .font(.headline)
                .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // All Services
                    categoryRow(nil, title: "All Services", count: servicePlugins.count)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Individual categories
                    ForEach(ServiceCategory.allCases, id: \.self) { category in
                        let count = servicePlugins.filter { $0.category == category }.count
                        if count > 0 {
                            categoryRow(category, title: category.rawValue, count: count)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func categoryRow(_ category: ServiceCategory?, title: String, count: Int) -> some View {
        HStack {
            if let category = category {
                Image(systemName: category.icon)
                    .frame(width: 20)
            } else {
                Image(systemName: "square.grid.3x3")
                    .frame(width: 20)
            }
            
            Text(title)
                .font(.system(size: 13))
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.tertiaryLabelColor).opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selectedCategory == category && (category != nil || selectedCategory == nil) ? 
                   Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategory = category
        }
    }
    
    // MARK: - Services Content
    
    private var servicesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Services")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search services...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 200)
                
                Button(action: { activeSheet = .install }) {
                    Label("Install Plugin", systemImage: "plus.circle")
                }
                
                Button(action: loadServicePlugins) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()
            
            Divider()
            
            // Services list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredPlugins) { plugin in
                        ServiceRow(plugin: plugin) {
                            activeSheet = .configure(plugin)
                        } onToggle: {
                            togglePlugin(plugin)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Filtering
    
    private var filteredPlugins: [ServicePluginInfo] {
        var plugins = servicePlugins
        
        // Filter by category
        if let category = selectedCategory {
            plugins = plugins.filter { $0.category == category }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            plugins = plugins.filter { plugin in
                plugin.name.localizedCaseInsensitiveContains(searchText) ||
                plugin.description.localizedCaseInsensitiveContains(searchText) ||
                plugin.identifier.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return plugins.sorted { $0.name < $1.name }
    }
    
    // MARK: - Actions
    
    private func loadServicePlugins() {
        servicePlugins = pluginManager.getAllPlugins()
    }
    
    private func togglePlugin(_ plugin: ServicePluginInfo) {
        if plugin.isEnabled {
            _ = pluginManager.disablePlugin(identifier: plugin.identifier)
        } else {
            _ = pluginManager.enablePlugin(identifier: plugin.identifier)
        }
        loadServicePlugins()
    }
    
    private func installPlugin(from url: URL) {
        let result = pluginManager.installPlugin(from: url)
        if !result.success {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Failed to install plugin"
            alert.informativeText = result.error ?? "Unknown error"
            alert.alertStyle = .warning
            alert.runModal()
        }
        loadServicePlugins()
    }
}

// MARK: - Service Row
struct ServiceRow: View {
    let plugin: ServicePluginInfo
    let onConfigure: () -> Void
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: plugin.category.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(plugin.name)
                        .font(.system(size: 14, weight: .medium))
                    
                    if plugin.isBuiltIn {
                        Text("Built-in")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(plugin.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(plugin.author, systemImage: "person")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.6))
                    
                    if !plugin.requiredPermissions.requiresAccessibility &&
                       !plugin.requiredPermissions.requiresFileAccess &&
                       !plugin.requiredPermissions.requiresNetworkAccess {
                        Label("No special permissions", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        permissionsLabel
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onConfigure) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Configure Service")
                
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(SwitchToggleStyle())
                .help(plugin.isEnabled ? "Disable Service" : "Enable Service")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var permissionsLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.shield")
            Text(permissionsText)
        }
        .font(.caption)
        .foregroundColor(.orange)
    }
    
    private var permissionsText: String {
        var permissions: [String] = []
        
        if plugin.requiredPermissions.requiresAccessibility {
            permissions.append("Accessibility")
        }
        if plugin.requiredPermissions.requiresFileAccess {
            permissions.append("Files")
        }
        if plugin.requiredPermissions.requiresNetworkAccess {
            permissions.append("Network")
        }
        if plugin.requiredPermissions.requiresScreenRecording {
            permissions.append("Screen")
        }
        
        return permissions.joined(separator: ", ")
    }
}

// MARK: - Service Configuration Sheet
struct ServiceConfigurationSheet: View {
    let plugin: ServicePluginInfo
    @Environment(\.dismiss) private var dismiss
    @State private var configOptions: [ServiceConfigOption] = []
    @State private var configValues: [String: Any] = [:]
    
    private let pluginManager = ServicePluginManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: plugin.category.icon)
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(plugin.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Configuration options
            if configOptions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No configuration options available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(configOptions) { option in
                            ConfigOptionView(option: option, value: binding(for: option.key))
                        }
                    }
                }
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Apply") {
                    applyConfiguration()
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            loadConfiguration()
        }
    }
    
    private func binding(for key: String) -> Binding<Any?> {
        Binding(
            get: { configValues[key] },
            set: { configValues[key] = $0 }
        )
    }
    
    private func loadConfiguration() {
        configOptions = pluginManager.getConfigurationOptions(for: plugin.identifier)
        
        // Initialize with default values
        for option in configOptions {
            configValues[option.key] = option.defaultValue
        }
    }
    
    private func applyConfiguration() {
        pluginManager.applyConfiguration(for: plugin.identifier, config: configValues)
    }
}

// MARK: - Config Option View
struct ConfigOptionView: View {
    let option: ServiceConfigOption
    @Binding var value: Any?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.label)
                .font(.system(size: 13, weight: .medium))
            
            if let description = option.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            optionControl
        }
    }
    
    @ViewBuilder
    private var optionControl: some View {
        switch option.type {
        case .boolean:
            Toggle("", isOn: Binding(
                get: { value as? Bool ?? false },
                set: { value = $0 }
            ))
            .toggleStyle(SwitchToggleStyle())
            
        case .integer(let min, let max):
            HStack {
                TextField("", value: Binding(
                    get: { value as? Int ?? 0 },
                    set: { value = $0 }
                ), format: .number)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if let min = min, let max = max {
                    Text("(\(min) - \(max))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
        case .string:
            TextField("", text: Binding(
                get: { value as? String ?? "" },
                set: { value = $0 }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            
        case .selection(let options):
            Picker("", selection: Binding(
                get: { value as? String ?? options.first ?? "" },
                set: { value = $0 }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
        default:
            Text("Unsupported option type")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Service Install Sheet
struct ServiceInstallSheet: View {
    let onInstall: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFile: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Install Service Plugin")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a .serviceplugin file to install")
                .foregroundColor(.secondary)
            
            Button("Choose File...") {
                chooseFile()
            }
            
            if let url = selectedFile {
                HStack {
                    Image(systemName: "doc.fill")
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Install") {
                    if let url = selectedFile {
                        onInstall(url)
                        dismiss()
                    }
                }
                .disabled(selectedFile == nil)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
    
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a service plugin file"
        
        if panel.runModal() == .OK {
            selectedFile = panel.url
        }
    }
}
