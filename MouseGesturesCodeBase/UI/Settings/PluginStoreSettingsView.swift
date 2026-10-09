import SwiftUI

// MARK: - Settings ▸ Plugins (Pro)
// A clean page listing the plugins people can install from the library. Everything that
// ships with the app, plugin sources, install-from-file and per-plugin diagnostics stay in the
// Developer tab's Plugin Management.

struct PluginStoreSettingsView: View {
    @ObservedObject private var license = LicenseService.shared

    var body: some View {
        if license.isPro {
            PluginLibrariesView(embedded: true)
        } else {
            lockedCard
        }
    }

    /// What free users see: the feature is Pro.
    private var lockedCard: some View {
        VStack(spacing: MGStyle.Spacing.lg) {
            Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundColor(.orange)
            Text("Plugins are a Pro feature").font(.headline)
            Text("Add timers and alarms, scheduled actions, text tools, new triggers and more from the official plugin library. Upgrade to Pro to unlock them.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("See License Options") {
                NotificationCenter.default.post(name: Notification.Name("MGOpenSettingsCategory"), object: "license")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
