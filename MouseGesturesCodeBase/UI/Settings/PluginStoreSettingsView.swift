import SwiftUI

// MARK: - Settings ▸ Plugins
// A clean page listing the plugins people can install from the library. Browsing is free; installing
// and updating need Pro (the page says so). Everything that ships with the app, plugin sources,
// install-from-file and per-plugin diagnostics stay in the Developer tab's Plugin Management.

struct PluginStoreSettingsView: View {
    var body: some View {
        PluginLibrariesView(embedded: true)
    }
}
