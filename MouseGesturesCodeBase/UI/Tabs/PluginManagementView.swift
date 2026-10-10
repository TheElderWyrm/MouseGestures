import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Plugin Management (Developer tab)
// Everything about installed plugins: the unified list (action, detection, service, UI),
// enable/disable, details, reload/uninstall, and the full Add Plugins sheet (including install from file).

struct PluginManagementView: View {
    @StateObject private var uiServices = UIServices.shared

    @State private var unifiedPlugins: [UnifiedPluginInfo] = []
    @State private var selectedUnifiedPlugin: UnifiedPluginInfo?
    @State private var pluginSearchText = ""
    @State private var selectedPluginType: UnifiedPluginType? = nil
    @State private var showingPluginDetails = false
    @State private var showingLibraries = false
    @State private var settingsPlugin: UnifiedPluginInfo?
    @State private var successMessage: String?
    @State private var errorMessage: String?
    private let servicePluginManager = ServicePluginManager.shared

    enum UnifiedPluginType: String, CaseIterable, Identifiable {
        case action = "Action"
        case detection = "Detection"
        case service = "Service"
        case ui = "UI"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .action: return "bolt.fill"
            case .detection: return "hand.tap.fill"
            case .service: return "gearshape.2.fill"
            case .ui: return "uiwindow.split.2x1"
            }
        }

        var color: Color {
            switch self {
            case .action: return .blue
            case .detection: return .orange
            case .service: return .green
            case .ui: return .purple
            }
        }
    }

    struct UnifiedPluginInfo: Identifiable {
        let id: String
        let identifier: String
        let name: String
        let type: UnifiedPluginType
        let version: String
        let author: String
        let description: String
        let isBuiltIn: Bool
        var isEnabled: Bool

        // Additional info
        var actionCount: Int? = nil
        var serviceCategory: ServiceCategory? = nil
        var uiCategory: UIPluginCategory? = nil
        var permissions: String = ""
    }


    var body: some View {
        pluginsSection
            .onAppear { refreshUnifiedPlugins() }
            .sheet(item: $settingsPlugin) { PluginSettingsSheet(pluginId: $0.identifier, pluginName: $0.name) }
            .sheet(isPresented: $showingLibraries) {
                PluginLibrariesView(onChange: { refreshUnifiedPlugins() },
                                    onInstallFile: { handlePluginInstall(result: $0) })
            }
    }

    private var messageBanner: some View {
        Group {
            if let m = successMessage { Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green) }
            if let m = errorMessage { Label(m, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.red) }
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Plugin Management")
            messageBanner

            // Search and Filters
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                MGContentCard {
                    VStack(spacing: MGStyle.Spacing.lg) {
                        HStack(spacing: MGStyle.Spacing.lg) {
                            MGSearchField("Search plugins...", text: $pluginSearchText)

                            Button(action: { refreshUnifiedPlugins() }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)

                            Button(action: { showingLibraries = true }) {
                                Label("Add Plugins", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack(spacing: MGStyle.Spacing.md) {
                            Text("Filter:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { selectedPluginType = nil }) {
                                Text("All")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedPluginType == nil ? Color.accentColor : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedPluginType == nil ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)

                            ForEach(UnifiedPluginType.allCases) { type in
                                Button(action: { selectedPluginType = type }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 10))
                                        Text(type.rawValue)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedPluginType == type ? type.color : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedPluginType == type ? .white : .primary)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Text("\(filteredPlugins.count) plugins")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Unified Plugin List
            if filteredPlugins.isEmpty {
                MGContentCard {
                    VStack(spacing: MGStyle.Spacing.lg) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(pluginSearchText.isEmpty ? "No plugins loaded" : "No plugins matching your search")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
            } else {
                MGContentCard {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredPlugins) { plugin in
                                unifiedPluginRow(plugin)
                                if plugin.id != filteredPlugins.last?.id {
                                    Divider().padding(.horizontal, MGStyle.Spacing.lg)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 500)
                }
            }

            if let plugin = selectedUnifiedPlugin {
                unifiedPluginDetailsView(plugin)
            }
        }
    }

    private var filteredPlugins: [UnifiedPluginInfo] {
        unifiedPlugins.filter { plugin in
            let matchesSearch = pluginSearchText.isEmpty ||
                plugin.name.localizedCaseInsensitiveContains(pluginSearchText) ||
                plugin.identifier.localizedCaseInsensitiveContains(pluginSearchText) ||
                plugin.description.localizedCaseInsensitiveContains(pluginSearchText)

            let matchesType = selectedPluginType == nil || plugin.type == selectedPluginType

            return matchesSearch && matchesType
        }
    }

    private func unifiedPluginRow(_ plugin: UnifiedPluginInfo) -> some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            Image(systemName: PluginSymbols.symbol(for: plugin.identifier, fallback: plugin.type.icon))
                .font(.system(size: 16))
                .foregroundColor(plugin.type.color)
                .frame(width: 28, height: 28)
                .background(plugin.type.color.opacity(0.12))
                .cornerRadius(MGStyle.Corner.lg)
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                HStack(spacing: MGStyle.Spacing.md) {
                    Text(plugin.name)
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))

                    // Type Chip
                    HStack(spacing: 4) {
                        Image(systemName: plugin.type.icon)
                            .font(.system(size: 8))
                        Text(plugin.type.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(plugin.type.color.opacity(0.15))
                    .foregroundColor(plugin.type.color)
                    .cornerRadius(4)

                    if plugin.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    }
                }

                Text(plugin.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: MGStyle.Spacing.xl) {
                if plugin.type == .action, let count = plugin.actionCount {
                    Text("\(count) actions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("v\(plugin.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(plugin.identifier)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { togglePlugin(plugin, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                MGActionButton("info.circle", help: "View details") {
                    selectedUnifiedPlugin = plugin
                }
            }
        }
        .padding(MGStyle.Spacing.lg)
        .contentShape(Rectangle())
        .onTapGesture { selectedUnifiedPlugin = plugin }
        .background(selectedUnifiedPlugin?.id == plugin.id ? MGStyle.Colors.selectedRow : Color.clear)
    }

    private func refreshUnifiedPlugins() {
        var allPlugins: [UnifiedPluginInfo] = []

        // 1. Action Plugins
        let actionPlugins = uiServices.getLoadedPlugins()
        for p in actionPlugins {
            allPlugins.append(UnifiedPluginInfo(
                id: "action-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .action,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.isBuiltIn,
                isEnabled: p.isEnabled,
                actionCount: p.actionCount,
                permissions: describePermissions(p.permissions)
            ))
        }

        // 2. Detection Plugins
        let detectionPlugins = DetectionPluginManager.shared.getAllPlugins()
        for p in detectionPlugins {
            allPlugins.append(UnifiedPluginInfo(
                id: "detection-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .detection,
                version: p.version,
                author: DetectionPluginManager.shared.isExternalPlugin(identifier: p.identifier) ? "External" : "System",
                description: p.description,
                isBuiltIn: !DetectionPluginManager.shared.isExternalPlugin(identifier: p.identifier),
                isEnabled: p.isEnabled,
                permissions: "Low-level Input"
            ))
        }

        // 3. Service Plugins
        let services = servicePluginManager.getAllPlugins()
        for p in services {
            allPlugins.append(UnifiedPluginInfo(
                id: "service-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .service,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.isBuiltIn,
                isEnabled: p.isEnabled,
                serviceCategory: p.category,
                permissions: describeServicePermissions(p.requiredPermissions)
            ))
        }

        // 4. UI Plugins
        let uiPlugs = UIPluginManager.shared.getAllPlugins()
        for p in uiPlugs {
            allPlugins.append(UnifiedPluginInfo(
                id: "ui-\(p.identifier)",
                identifier: p.identifier,
                name: p.displayName,
                type: .ui,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.sortOrder < 100,
                isEnabled: UIPluginManager.shared.isPluginEnabled(identifier: p.identifier),
                uiCategory: p.category,
                permissions: "UI/Management"
            ))
        }

        unifiedPlugins = allPlugins
        if let selected = selectedUnifiedPlugin {
            selectedUnifiedPlugin = unifiedPlugins.first(where: { $0.id == selected.id })
        }
    }

    private func describeServicePermissions(_ p: ServicePermissions) -> String {
        var perms: [String] = []
        if p.requiresAccessibility { perms.append("Accessibility") }
        if p.requiresFileAccess { perms.append("Files") }
        if p.requiresNetworkAccess { perms.append("Network") }
        if p.requiresNotifications { perms.append("Notifications") }
        if p.requiresScreenRecording { perms.append("Screen") }
        if p.requiresAutomation { perms.append("Automation") }
        if p.requiresFullDiskAccess { perms.append("Full Disk") }
        return perms.isEmpty ? "None" : perms.joined(separator: ", ")
    }

    private func togglePlugin(_ plugin: UnifiedPluginInfo, enabled: Bool) {
        switch plugin.type {
        case .action:
            if enabled { _ = uiServices.reloadPlugin(plugin.identifier) } else { _ = uiServices.uninstallPlugin(plugin.identifier) }
            PluginLibraryService.shared.reconcile()
        case .detection:
            DetectionPluginManager.shared.setPluginEnabled(plugin.identifier, enabled: enabled)
        case .service:
            if enabled { _ = servicePluginManager.enablePlugin(identifier: plugin.identifier) } else { _ = servicePluginManager.disablePlugin(identifier: plugin.identifier) }
        case .ui:
            UIPluginManager.shared.setPluginEnabled(identifier: plugin.identifier, enabled: enabled)
        }
        refreshUnifiedPlugins()
    }

    private func handlePluginInstall(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Unified installation logic: autodetect by extension
            let ext = url.pathExtension.lowercased()

            if (ext == "plugin" || ext == "auraplugin"),
               Bundle(url: url)?.object(forInfoDictionaryKey: "MGPluginKind") as? String == "detection" {
                do {
                    try DetectionPluginManager.shared.installExternalPlugin(from: url)
                    successMessage = "Detection plugin installed"
                    PluginLibraryService.shared.reconcile()
                    refreshUnifiedPlugins()
                } catch { errorMessage = "Failed to install detection plugin: \(error.localizedDescription)" }
            } else if ext == "plugin" || ext == "auraplugin" {
                if uiServices.installPlugin(from: url) {
                    successMessage = "Action plugin installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = uiServices.errorMessage ?? "Failed to install action plugin" }
            } else if ext == "service" {
                let res = servicePluginManager.installPlugin(from: url)
                if res.success {
                    successMessage = "Service installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = res.error ?? "Failed to install service" }
            } else if ext == "uiplugin" {
                let dest = Configuration.applicationSupportDirectory.appendingPathComponent("UIPlugins").appendingPathComponent(url.lastPathComponent)
                do {
                    try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.copyItem(at: url, to: dest)
                    successMessage = "UI plugin installed. Restart app to activate."
                    refreshUnifiedPlugins()
                } catch { errorMessage = "Failed to install UI plugin: \(error.localizedDescription)" }
            } else {
                if uiServices.installPlugin(from: url) {
                    successMessage = "Plugin installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = "Unsupported plugin format" }
            }
        case .failure(let error): errorMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    private func uninstallUnifiedPlugin(_ plugin: UnifiedPluginInfo) {
        switch plugin.type {
        case .action: _ = uiServices.uninstallPlugin(plugin.identifier)
        case .service: _ = servicePluginManager.uninstallPlugin(identifier: plugin.identifier)
        case .ui: errorMessage = "Manually remove from UIPlugins folder"
        case .detection:
            do { try DetectionPluginManager.shared.uninstallExternalPlugin(identifier: plugin.identifier) }
            catch { errorMessage = "Failed to uninstall detection plugin: \(error.localizedDescription)" }
        }
        PluginLibraryService.shared.reconcile()
        refreshUnifiedPlugins()
        selectedUnifiedPlugin = nil
    }

    private func reloadUnifiedPlugin(_ plugin: UnifiedPluginInfo) {
        switch plugin.type {
        case .action: _ = uiServices.reloadPlugin(plugin.identifier)
        case .service:
            _ = servicePluginManager.disablePlugin(identifier: plugin.identifier)
            _ = servicePluginManager.enablePlugin(identifier: plugin.identifier)
        default: break
        }
        refreshUnifiedPlugins()
    }

    private func unifiedPluginDetailsView(_ plugin: UnifiedPluginInfo) -> some View {
        MGContentCard {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(.headline)
                        Text(plugin.identifier).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if PluginExtensionManager.shared.hasSettingsUI(plugin.identifier) {
                        Button("Settings…") { settingsPlugin = plugin }
                    }
                    if !plugin.isBuiltIn {
                        HStack(spacing: MGStyle.Spacing.md) {
                            Button("Reload") { reloadUnifiedPlugin(plugin) }
                            Button("Uninstall", role: .destructive) { uninstallUnifiedPlugin(plugin) }
                                .foregroundColor(.red)
                        }
                    }
                    Button("Close") { selectedUnifiedPlugin = nil }.buttonStyle(.plain).foregroundColor(.secondary)
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: MGStyle.Spacing.xl, verticalSpacing: MGStyle.Spacing.md) {
                    GridRow { Text("Type").foregroundColor(.secondary); Text(plugin.type.rawValue) }
                    GridRow { Text("Version").foregroundColor(.secondary); Text(plugin.version) }
                    GridRow { Text("Author").foregroundColor(.secondary); Text(plugin.author) }
                    GridRow { Text("Status").foregroundColor(.secondary); Text(plugin.isEnabled ? "Active" : "Disabled") }
                    GridRow { Text("Permissions").foregroundColor(.secondary); Text(plugin.permissions).font(.caption) }
                }
                .font(.caption)
                Text(plugin.description).font(.callout).padding(.top, 4)
            }
            .padding(MGStyle.Spacing.lg)
        }
    }

    private func describePermissions(_ permissions: PluginPermissions) -> String {
        if permissions == .builtIn { return "Full Access (Built-in)" } else if permissions == .restricted { return "Restricted" } else {
            var perms: [String] = []
            if permissions.canAccessFileSystem { perms.append("Files") }
            if permissions.canAccessNetwork { perms.append("Network") }
            if permissions.canAccessSystemAPIs { perms.append("System") }
            if permissions.canExecuteOtherActions { perms.append("Actions") }
            if permissions.canShowNotifications { perms.append("Notifications") }
            return perms.isEmpty ? "None" : perms.joined(separator: ", ")
        }
    }

    /// Reloads every installed (non-built-in) action plugin; used by the Developer tab's diagnostics.
    static func reloadAllExternalPlugins() {
        let services = UIServices.shared
        for p in services.getLoadedPlugins() where !p.isBuiltIn { _ = services.reloadPlugin(p.identifier) }
    }
}
