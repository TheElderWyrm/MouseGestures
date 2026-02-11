import SwiftUI

// MARK: - Plugin-Based Tab Manager

struct TabManager: View {
    @StateObject private var uiPluginManager = UIPluginManager.shared
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedTabID: String = ""
    @State private var previousTabID: String = ""
    // Memory optimization: Track which tabs have been loaded to enable lazy loading
    @State private var loadedTabs: Set<String> = []
    
    var body: some View {
        Group {
            if uiPluginManager.isLoading || uiPluginManager.visiblePlugins.isEmpty {
                // Show loading state until plugins are ready, prevents invalid variadic child access
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(width: 1000, height: 700)
            } else {
                TabView(selection: $selectedTabID) {
                    ForEach(uiPluginManager.visiblePlugins, id: \.identifier) { plugin in
                        createTabItem(for: plugin)
                    }
                }
                .frame(width: 1000, height: 700)
                .onChange(of: selectedTabID) { newValue in
                    // Mark the new tab as loaded before handling the change
                    loadedTabs.insert(newValue)
                    handleTabChange(from: previousTabID, to: newValue)
                    previousTabID = newValue
                }
                .onAppear {
                    initializeFirstTab()
                }
            }
        }
    }
    
    /// Set up the initial tab selection once plugins are available
    private func initializeFirstTab() {
        guard let firstPlugin = uiPluginManager.visiblePlugins.first else { return }
        let firstID = firstPlugin.identifier
        if selectedTabID.isEmpty {
            loadedTabs.insert(firstID)
            selectedTabID = firstID
            previousTabID = firstID
        }
        Task { @MainActor in
            uiPluginManager.activatePlugin(identifier: firstID)
        }
    }
    
    @ViewBuilder
    private func createTabItem(for plugin: any UIPlugin) -> some View {
        // Memory optimization: Only create the actual view if this tab has been selected
        // This prevents all 8+ tabs from being rendered at startup
        Group {
            if loadedTabs.contains(plugin.identifier) {
                plugin.createView()
            } else {
                // Lightweight placeholder until tab is first selected
                LazyTabPlaceholder(pluginName: plugin.displayName)
            }
        }
        .tabItem {
            Label(plugin.displayName, systemImage: plugin.iconName)
        }
        .tag(plugin.identifier)
    }
    
    private func handleTabChange(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        
        // Deactivate old plugin
        if !oldID.isEmpty {
            Task { @MainActor in
                uiPluginManager.deactivatePlugin(identifier: oldID)
            }
        }
        
        // Activate new plugin
        if !newID.isEmpty {
            Task { @MainActor in
                uiPluginManager.activatePlugin(identifier: newID)
            }
        }
    }
}

// MARK: - Dynamic Tab Manager (Alternative Implementation)

struct DynamicTabManager: View {
    @StateObject private var uiPluginManager = UIPluginManager.shared
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedPluginID: String?
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with plugin list
            List(uiPluginManager.visiblePlugins, id: \.identifier, selection: $selectedPluginID) { plugin in
                NavigationLink(value: plugin.identifier) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(plugin.displayName)
                                .font(.headline)
                            if !plugin.description.isEmpty {
                                Text(plugin.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: plugin.iconName)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            .navigationTitle("MouseGestures")
        } detail: {
            // Detail view with selected plugin
            if let selectedID = selectedPluginID,
               let plugin = uiPluginManager.getPlugin(identifier: selectedID) {
                plugin.createView()
                    .navigationTitle(plugin.displayName)
                    .navigationSubtitle("v\(plugin.version) by \(plugin.author)")
            } else {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView {
                        Label("Select a Section", systemImage: "sidebar.left")
                    } description: {
                        Text("Choose a section from the sidebar")
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Select a Section")
                            .font(.headline)
                        Text("Choose a section from the sidebar")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 1000, height: 700)
        .onChange(of: selectedPluginID) { newValue in
            handlePluginChange(to: newValue)
        }
        .onAppear {
            // Select the first plugin by default
            if selectedPluginID == nil,
               let firstPlugin = uiPluginManager.visiblePlugins.first {
                selectedPluginID = firstPlugin.identifier
            }
        }
    }
    
    private func handlePluginChange(to newPluginID: String?) {
        // Deactivate all plugins
        for plugin in uiPluginManager.visiblePlugins {
            if plugin.identifier != newPluginID {
                Task { @MainActor in
                    uiPluginManager.deactivatePlugin(identifier: plugin.identifier)
                }
            }
        }
        
        // Activate selected plugin
        if let pluginID = newPluginID {
            Task { @MainActor in
                uiPluginManager.activatePlugin(identifier: pluginID)
            }
        }
    }
}

// MARK: - Plugin Tab Manager Settings

struct PluginTabManagerSettings: View {
    @StateObject private var uiPluginManager = UIPluginManager.shared
    @State private var showingPluginManager = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("UI Plugins")
            
            Text("Manage which tabs are visible in the application")
                .foregroundColor(.secondary)
            
            Divider()
            
            // Plugin list
            ScrollView {
                VStack(spacing: MGStyle.Spacing.lg) {
                    ForEach(Array(uiPluginManager.loadedPlugins.values), id: \.identifier) { plugin in
                        PluginRow(plugin: plugin)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Manage Plugins...") {
                    showingPluginManager = true
                }
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await refreshPlugins()
                    }
                }
            }
        }
        .padding(MGStyle.Spacing.xxl)
        .frame(width: 600, height: 400)
        .sheet(isPresented: $showingPluginManager) {
            PluginManagerView()
        }
    }
    
    private func refreshPlugins() async {
        // Reload all plugins
        for plugin in uiPluginManager.loadedPlugins.values {
            await uiPluginManager.reloadPlugin(identifier: plugin.identifier)
        }
    }
}

struct PluginRow: View {
    let plugin: any UIPlugin
    @StateObject private var uiPluginManager = UIPluginManager.shared
    
    var isEnabled: Bool {
        uiPluginManager.isPluginEnabled(identifier: plugin.identifier)
    }
    
    var body: some View {
        HStack {
            Image(systemName: plugin.iconName)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(plugin.displayName)
                    .font(.headline)
                
                Text("\(plugin.category.displayName) • v\(plugin.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: .constant(isEnabled))
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { newValue in
                    if newValue {
                        uiPluginManager.enablePlugin(identifier: plugin.identifier)
                    } else {
                        uiPluginManager.disablePlugin(identifier: plugin.identifier)
                    }
                }
        }
        .padding(.vertical, MGStyle.Spacing.sm)
    }
}

struct PluginManagerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Plugin Manager")
            
            Text("Install and manage UI plugins")
                .foregroundColor(.secondary)
            
            Spacer()
            
            MGEmptyState(
                icon: "shippingbox",
                title: "Plugin marketplace coming soon..."
            )
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding(MGStyle.Spacing.xxl)
        .frame(width: 500, height: 400)
    }
}

// MARK: - Lazy Tab Placeholder

/// Memory optimization: Lightweight placeholder shown for tabs that haven't been selected yet
/// This prevents all plugin views from being instantiated at startup
struct LazyTabPlaceholder: View {
    let pluginName: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading \(pluginName)...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
