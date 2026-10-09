import SwiftUI

/// Settings ▸ Actions & Triggers: one tab per built-in plugin that has options (like Detection's tabs).
struct BuiltInPluginsSettingsProvider: SettingsProvider {
    private static let icons: [String: String] = [
        "com.mousegestures.timers": "timer", "com.mousegestures.pointer": "cursorarrow.motionlines",
        "com.mousegestures.text": "textformat", "com.mousegestures.browser": "safari",
        "com.mousegestures.system": "gearshape.2", "com.mousegestures.media": "speaker.wave.2"
    ]

    private static let keywords: [String: [String]] = [
        "com.mousegestures.timers": ["timer", "alarm", "pomodoro", "stopwatch", "sound", "minutes"],
        "com.mousegestures.pointer": ["shake", "circle", "corner", "dwell", "pointer", "modifier"],
        "com.mousegestures.text": ["text", "case", "format", "snippet", "clipboard"],
        "com.mousegestures.browser": ["search", "engine", "google", "browser", "web"]
    ]

    var settingsEntries: [SettingsEntry] {
        PluginExtensionManager.shared.builtInPluginsWithSettings().enumerated().map { index, plugin in
            let sub = SettingsSubcategoryDescriptor(id: plugin.id, title: plugin.name,
                                                    icon: Self.icons[plugin.id] ?? "puzzlepiece.extension", order: index)
            let fields = PluginExtensionManager.shared.fields(plugin.id)
            let words = Self.keywords[plugin.id] ?? [plugin.name.lowercased()]
            let items = (fields.isEmpty ? [plugin.name] : fields.map { $0.title }).map {
                SearchableSettingItem(title: $0, description: "\(plugin.name) option", keywords: words)
            }
            return SettingsEntry(category: SettingsCategories.features, subcategory: sub, order: index, searchableItems: items,
                                 viewBuilder: { _ in AnyView(PluginSettingsSheet(pluginId: plugin.id, pluginName: plugin.name, embedded: true)) })
        }
    }
}

/// Settings ▸ Plugins (Pro): browse and install plugins from the library.
struct PluginsSettingsProvider: SettingsProvider {
    var settingsEntries: [SettingsEntry] {
        [
            SettingsEntry(
                category: SettingsCategories.plugins,
                order: 0,
                searchableItems: [
                    SearchableSettingItem(
                        title: "Plugins", description: "Browse, install and update plugins from the official library",
                        keywords: ["plugin", "plugins", "library", "install", "extension", "schedule", "clipboard", "pro"])
                ],
                viewBuilder: { _ in AnyView(PluginStoreSettingsView()) }
            )
        ]
    }
}
