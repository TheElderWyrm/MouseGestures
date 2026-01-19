import SwiftUI

// MARK: - Plugin-Based Tab Manager

struct TabManager: View {
    @State private var selectedTab = 0
    @StateObject private var uiPluginManager = UIPluginManager.shared
    @StateObject private var uiServices = UIServices.shared
    @State private var previousSelectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Array(uiPluginManager.visiblePlugins.enumerated()), id: \.element.identifier) { index, plugin in
                createTabItem(for: plugin, tag: index)
            }
        }
        .frame(width: 1000, height: 700)
        .onChange(of: selectedTab) { newValue in
            handleTabChange(from: previousSelectedTab, to: newValue)
            previousSelectedTab = newValue
        }
        .onAppear {
            // Activate the first plugin
            if let firstPlugin = uiPluginManager.visiblePlugins.first {
                Task { @MainActor in
                    uiPluginManager.activatePlugin(identifier: firstPlugin.identifier)
                }
            }
        }
    }
    
    @ViewBuilder
    private func createTabItem(for plugin: any UIPlugin, tag: Int) -> some View {
        plugin.createView()
            .tabItem {
                Label(plugin.displayName, systemImage: plugin.iconName)
            }
            .tag(tag)
    }
    
    private func handleTabChange(from oldIndex: Int, to newIndex: Int) {
        let plugins = uiPluginManager.visiblePlugins
        
        // Deactivate old plugin
        if oldIndex >= 0 && oldIndex < plugins.count {
            let oldPlugin = plugins[oldIndex]
            Task { @MainActor in
                uiPluginManager.deactivatePlugin(identifier: oldPlugin.identifier)
            }
        }
        
        // Activate new plugin
        if newIndex >= 0 && newIndex < plugins.count {
            let newPlugin = plugins[newIndex]
            Task { @MainActor in
                uiPluginManager.activatePlugin(identifier: newPlugin.identifier)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("UI Plugins")
                .font(.title2)
                .bold()
            
            Text("Manage which tabs are visible in the application")
                .foregroundColor(.secondary)
            
            Divider()
            
            // Plugin list
            ScrollView {
                VStack(spacing: 12) {
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
        .padding()
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
            
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 4)
    }
}

struct PluginManagerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Plugin Manager")
                .font(.title)
            
            Text("Install and manage UI plugins")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Plugin marketplace coming soon...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
