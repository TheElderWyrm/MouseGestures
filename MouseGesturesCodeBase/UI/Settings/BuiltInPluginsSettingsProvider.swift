import SwiftUI

/// Settings ▸ Actions (one tab per action plugin with options) and Settings ▸ Detection (a tab for each trigger plugin
/// with options, beside the zone and app-profile tabs). Built-in and installed library plugins both appear.
struct BuiltInPluginsSettingsProvider: SettingsProvider {
    private static let icons: [String: String] = [
        "com.mousegestures.timers": "timer", "com.mousegestures.pointer": "cursorarrow.motionlines",
        "com.mousegestures.text": "textformat", "com.mousegestures.browser": "safari",
        "com.mousegestures.system": "gearshape.2", "com.mousegestures.media": "speaker.wave.2",
        "com.mousegestures.lib.clipboard": "list.clipboard", "com.mousegestures.lib.systemevents": "bolt.badge.clock",
        "com.mousegestures.lib.scheduler": "calendar.badge.clock", "com.mousegestures.lib.finderhelpers": "folder.badge.gearshape",
        "com.mousegestures.lib.screentools": "eyedropper"
    ]

    /// Short tab labels, so the segmented picker never gets cramped.
    private static let tabTitles: [String: String] = [
        "com.mousegestures.timers": "Timers", "com.mousegestures.browser": "Browser",
        "com.mousegestures.pointer": "Pointer Gestures", "com.mousegestures.lib.clipboard": "Clipboard",
        "com.mousegestures.lib.systemevents": "System Events", "com.mousegestures.lib.finderhelpers": "Finder",
        "com.mousegestures.lib.screentools": "Screen"
    ]

    private static let keywords: [String: [String]] = [
        "com.mousegestures.timers": ["timer", "alarm", "pomodoro", "stopwatch", "sound", "minutes"],
        "com.mousegestures.pointer": ["shake", "circle", "corner", "dwell", "pointer", "modifier"],
        "com.mousegestures.text": ["text", "case", "format", "snippet", "clipboard"],
        "com.mousegestures.browser": ["search", "engine", "google", "browser", "web"]
    ]

    var settingsEntries: [SettingsEntry] {
        let detectionIds = Set(DetectionPluginManager.shared.getAllPlugins().map { $0.identifier })
        return PluginExtensionManager.shared.pluginsWithSettings().enumerated().map { index, plugin in
            let isTrigger = detectionIds.contains(plugin.id)
            // Detection already has General / Zones / App Profiles tabs (0–2); ours follow.
            let sub = SettingsSubcategoryDescriptor(id: plugin.id, title: Self.tabTitles[plugin.id] ?? plugin.name,
                                                    icon: Self.icons[plugin.id] ?? "puzzlepiece.extension",
                                                    order: isTrigger ? 10 + index : index)
            let fields = PluginExtensionManager.shared.fields(plugin.id)
            let words = Self.keywords[plugin.id] ?? [plugin.name.lowercased()]
            let items = (fields.isEmpty ? [plugin.name] : fields.map { $0.title }).map {
                SearchableSettingItem(title: $0, description: "\(plugin.name) option", keywords: words)
            }
            return SettingsEntry(category: isTrigger ? SettingsCategories.detection : SettingsCategories.features,
                                 subcategory: sub, order: index, searchableItems: items,
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
