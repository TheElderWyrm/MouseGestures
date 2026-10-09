import SwiftUI

// MARK: - Settings ▸ Actions & Triggers
// Settings for the plugins that ship inside the app and have options: Timers & Alarms, Scheduler,
// Pointer Gestures, Text, Browser Actions (search engine), and so on. Each opens the same settings
// sheet library plugins use.

private struct BuiltInTarget: Identifiable { let id: String; let name: String }

struct BuiltInPluginsSettingsView: View {
    @ObservedObject private var extensions = PluginExtensionManager.shared
    @State private var target: BuiltInTarget?

    var body: some View {
        let plugins = extensions.builtInPluginsWithSettings()
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("Options for the actions and triggers built into MouseGestures. Pick them when you edit a gesture.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(plugins, id: \.id) { plugin in
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name).font(.system(size: 13, weight: .semibold))
                        Text(summary(for: plugin.id)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Settings…") { target = BuiltInTarget(id: plugin.id, name: plugin.name) }
                }
            }
            if plugins.isEmpty { Text("No built-in plugins have options.").font(.caption).foregroundColor(.secondary) }
        }
        .sheet(item: $target) { PluginSettingsSheet(pluginId: $0.id, pluginName: $0.name) }
    }

    private func summary(for id: String) -> String {
        if let plugin = PluginManager.shared.getPlugin(identifier: id) { return plugin.description }
        return DetectionPluginManager.shared.getAllPlugins().first { $0.identifier == id }?.description ?? ""
    }
}
