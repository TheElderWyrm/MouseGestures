import SwiftUI

// MARK: - Plugin-Based Tab Manager

struct TabManager: View {
    @StateObject private var uiPluginManager = UIPluginManager.shared
    @StateObject private var uiServices = UIServices.shared
    @StateObject private var licenseService = LicenseService.shared
    @StateObject private var tutorialService = TutorialService.shared
    @ObservedObject private var selfUpdateService = SelfUpdateService.shared
    @State private var selectedTabID: String = ""
    @State private var previousTabID: String = ""
    // Memory optimization: Track which tabs have been loaded to enable lazy loading
    @State private var loadedTabs: Set<String> = []

    @State private var showingUpdateNotification = false

    var body: some View {
        Group {
            if !uiServices.isOnboardingCompleted {
                OnboardingView {
                    uiServices.setOnboardingCompleted(true)
                }
            } else if uiPluginManager.isLoading || uiPluginManager.visiblePlugins.isEmpty {
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

                    if licenseService.status != .pro {
                        LicenseSettingsView()
                            .tabItem {
                                Label("Upgrade", systemImage: "star.fill")
                            }
                            .tag("com.mousegestures.ui.upgrade")
                    }
                }
                .frame(width: 1000, height: 700)
                .onChange(of: selectedTabID) { newValue in
                    // Mark the new tab as loaded before handling the change
                    loadedTabs.insert(newValue)
                    handleTabChange(from: previousTabID, to: newValue)
                    previousTabID = newValue
                }
                .onChange(of: tutorialService.state) { newState in
                    if newState == .start {
                        let gesturesTabID = "com.mousegestures.ui.gestures"
                        selectedTabID = gesturesTabID
                        loadedTabs.insert(gesturesTabID)
                        tutorialService.advance(from: .start, to: .clickAddGesture)
                    }
                }
                .onAppear {
                    initializeFirstTab()
                }
                .sheet(isPresented: $showingUpdateNotification) {
                    UpdateNotificationView()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MGUpdateAvailable"))) { _ in
                    showingUpdateNotification = true
                }
                .onChange(of: selfUpdateService.stage) { newStage in
                    // Dismiss through SwiftUI's own binding as soon as we're
                    // about to relaunch, rather than letting
                    // SelfUpdateService end the sheet at the raw AppKit
                    // level -- doing both fights over the same sheet and
                    // produces a visible close/reopen/close flicker right
                    // before quitting.
                    if case .relaunching = newStage {
                        showingUpdateNotification = false
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openUpgradeTab)) { _ in
                    selectedTabID = "com.mousegestures.ui.upgrade"
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
                ZStack {
                    plugin.createView()

                    if plugin.isPro && !licenseService.isPro {
                        ProGatedTabOverlay()
                    }
                }
            } else {
                // Lightweight placeholder until tab is first selected
                LazyTabPlaceholder(pluginName: plugin.displayName)
            }
        }
        .tabItem {
            if plugin.isPro && !licenseService.isPro {
                Label(plugin.displayName, systemImage: "lock.fill")
            } else {
                Label(plugin.displayName, systemImage: plugin.iconName)
            }
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

            // Bind to a real get/set binding: `.constant(isEnabled)` made the
            // toggle a read-only display that could never change the plugin's
            // enabled state, so the switch visually flipped back instantly and
            // the onChange branch above was dead. The set side drives the
            // uiPluginManager, whose @Published change re-evaluates `isEnabled`.
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    if newValue {
                        uiPluginManager.enablePlugin(identifier: plugin.identifier)
                    } else {
                        uiPluginManager.disablePlugin(identifier: plugin.identifier)
                    }
                }
            ))
            .toggleStyle(.switch)
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

struct ProGatedTabOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

                Text("Pro Feature")
                    .font(.title).fontWeight(.bold)

                Text("This tab is only available with a Pro license.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 300)

                Text("Upgrade to unlock unlimited profiles, app-specific targeting, and advanced automation.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 20).fill(MGStyle.Colors.contentBackground))
            .shadow(radius: 20)
        }
    }
}
