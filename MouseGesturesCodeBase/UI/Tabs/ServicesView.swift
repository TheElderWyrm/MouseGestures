import SwiftUI

// MARK: - Services View
struct ServicesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var servicePlugins: [ServicePluginInfo] = []
    @State private var selectedCategory: ServiceCategory?
    @State private var searchText = ""
    
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
            categorySidebar
                .frame(minWidth: MGStyle.Layout.sidebarMinWidth, idealWidth: MGStyle.Layout.sidebarIdealWidth, maxWidth: MGStyle.Layout.sidebarMaxWidth)
            
            servicesContent
                .frame(minWidth: 400)
        }
        .onAppear { loadServicePlugins() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .configure(let plugin):
                ServiceConfigurationSheet(plugin: plugin)
            case .install:
                ServiceInstallSheet { url in installPlugin(from: url) }
            }
        }
    }
    
    // MARK: - Category Sidebar
    
    private var categorySidebar: some View {
        MGSidebar(title: "Categories") {
            MGSidebarItem(
                title: "All Services",
                icon: "square.grid.3x3",
                isSelected: selectedCategory == nil,
                action: { selectedCategory = nil }
            )
            
            Divider().padding(.vertical, MGStyle.Spacing.sm)
            
            ForEach(ServiceCategory.allCases, id: \.self) { category in
                let count = servicePlugins.filter { $0.category == category }.count
                if count > 0 {
                    MGSidebarItem(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
        }
    }
    
    // MARK: - Services Content
    
    private var servicesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                HStack(spacing: MGStyle.Spacing.lg) {
                    MGSectionHeader("Services", icon: "gearshape.2")
                    
                    Spacer()
                    
                    MGSearchField("Search services...", text: $searchText)
                        .frame(width: 180)
                    
                    Button(action: loadServicePlugins) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                }
                
                if filteredPlugins.isEmpty {
                    MGEmptyState(
                        icon: "gearshape.2",
                        title: searchText.isEmpty ? "No services available" : "No matching services"
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                        ForEach(filteredPlugins) { plugin in
                            ServiceRow(plugin: plugin) {
                                activeSheet = .configure(plugin)
                            } onToggle: {
                                togglePlugin(plugin)
                            }
                        }
                    }
                }
            }
            .padding(MGStyle.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Filtering
    
    private var filteredPlugins: [ServicePluginInfo] {
        var plugins = servicePlugins
        if let category = selectedCategory {
            plugins = plugins.filter { $0.category == category }
        }
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
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            Image(systemName: plugin.category.icon)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                HStack {
                    Text(plugin.name)
                        .font(.system(size: MGStyle.FontSize.heading, weight: .medium))
                    
                    if plugin.isBuiltIn {
                        MGBadge("Built-in", color: .blue)
                    }
                    
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(plugin.description)
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: MGStyle.Spacing.lg) {
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
            
            HStack(spacing: MGStyle.Spacing.md) {
                MGActionButton("gearshape", help: "Configure Service") { onConfigure() }
                
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(SwitchToggleStyle())
                .help(plugin.isEnabled ? "Disable Service" : "Enable Service")
            }
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.lg)
        .mgListCard(isHovered: isHovered)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
    }
    
    private var permissionsLabel: some View {
        HStack(spacing: MGStyle.Spacing.sm) {
            Image(systemName: "lock.shield")
            Text(permissionsText)
        }
        .font(.caption)
        .foregroundColor(.orange)
    }
    
    private var permissionsText: String {
        var permissions: [String] = []
        if plugin.requiredPermissions.requiresAccessibility { permissions.append("Accessibility") }
        if plugin.requiredPermissions.requiresFileAccess { permissions.append("Files") }
        if plugin.requiredPermissions.requiresNetworkAccess { permissions.append("Network") }
        if plugin.requiredPermissions.requiresScreenRecording { permissions.append("Screen") }
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
        VStack(spacing: 0) {
            MGSheetHeader(
                plugin.name,
                subtitle: plugin.description,
                onCancel: { dismiss() }
            )
            
            if configOptions.isEmpty {
                MGEmptyState(icon: "gearshape.2", title: "No configuration options available")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                        ForEach(configOptions) { option in
                            ConfigOptionView(option: option, value: binding(for: option.key))
                        }
                    }
                    .padding(MGStyle.Spacing.xxl)
                }
            }
            
            MGSheetFooter("Apply") {
                applyConfiguration()
                dismiss()
            }
        }
        .frame(width: 500, height: 400)
        .onAppear { loadConfiguration() }
    }
    
    private func binding(for key: String) -> Binding<Any?> {
        Binding(
            get: { configValues[key] },
            set: { configValues[key] = $0 }
        )
    }
    
    private func loadConfiguration() {
        configOptions = pluginManager.getConfigurationOptions(for: plugin.identifier)
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
        VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
            Text(option.label)
                .font(.system(size: MGStyle.FontSize.body, weight: .medium))
            
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
        VStack(spacing: 0) {
            MGSheetHeader("Install Service Plugin", subtitle: "Select a .serviceplugin file to install", onCancel: { dismiss() })
            
            VStack(spacing: MGStyle.Spacing.xl) {
                Spacer()
                
                Button("Choose File...") { chooseFile() }
                
                if let url = selectedFile {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                    .padding(MGStyle.Spacing.xl)
                    .background(
                        RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                            .fill(MGStyle.Colors.cardBackground)
                    )
                }
                
                Spacer()
            }
            .padding(MGStyle.Spacing.xl)
            
            MGSheetFooter("Install", disabled: selectedFile == nil) {
                if let url = selectedFile {
                    onInstall(url)
                    dismiss()
                }
            }
        }
        .frame(width: 400, height: 250)
    }
    
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a service plugin file"
        if panel.runModal() == .OK { selectedFile = panel.url }
    }
}
