import SwiftUI
import AppKit

/// Settings sheet for a library plugin: a form generated from its declared
/// fields, its service switch, and any custom view the plugin supplies.
struct PluginSettingsSheet: View {
    let pluginId: String
    let pluginName: String
    /// Shown as a Settings tab instead of a sheet: no title or Done button, and Settings does the scrolling.
    var embedded = false
    @ObservedObject private var manager = PluginExtensionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var customView: NSView?

    var body: some View {
        let _ = manager.revision // re-render when a value changes
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            if !embedded {
                HStack {
                    Text("\(pluginName) Settings").font(.title2.bold())
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            scrolling {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                    if manager.runsService(pluginId) {
                        Toggle(isOn: Binding(get: { manager.serviceEnabled(pluginId) },
                                             set: { manager.setServiceEnabled(pluginId, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Background service").font(.system(size: 13, weight: .medium))
                                Text(manager.isServiceRunning(pluginId) ? "Running" : "Stopped")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Divider()
                    }
                    ForEach(manager.fields(pluginId), id: \.key) { field in fieldRow(field) }
                    if let customView = customView {
                        PluginCustomViewHost(view: customView)
                    }
                }
            }
        }
        .padding(embedded ? 0 : MGStyle.Spacing.xl)
        .frame(minWidth: embedded ? 0 : 460, minHeight: embedded ? 0 : 320)
        .onAppear { customView = manager.makeCustomView(pluginId) }
    }

    @ViewBuilder private func scrolling<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if embedded { content() } else { ScrollView { content() } }
    }

    // MARK: fields

    private func binding<T>(_ f: PluginSettingField, _ fallback: T, _ convert: @escaping (Any?) -> T?) -> Binding<T> {
        Binding(get: { convert(manager.value(pluginId, f.key)) ?? fallback },
                set: { manager.setSetting(pluginId, f.key, $0) })
    }

    @ViewBuilder
    private func fieldRow(_ f: PluginSettingField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch f.kind {
            case .toggle:
                Toggle(f.title, isOn: binding(f, false) { ($0 as? Bool) ?? ($0 as? NSNumber)?.boolValue })
            case .text(let placeholder):
                labeled(f) { TextField(placeholder ?? "", text: binding(f, "") { $0 as? String }).textFieldStyle(.roundedBorder) }
            case .number(let lo, let hi, let step, let unit):
                let v = binding(f, lo) { ($0 as? NSNumber)?.doubleValue }
                labeled(f) {
                    HStack {
                        Stepper(value: v, in: lo...Swift.max(lo, hi), step: step) {
                            Text(String(format: step < 1 ? "%.2f" : "%.0f", v.wrappedValue) + (unit.map { " \($0)" } ?? ""))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                }
            case .choice(let choices):
                labeled(f) {
                    Picker("", selection: binding(f, choices.first?.value ?? "") { $0 as? String }) {
                        ForEach(choices, id: \.value) { Text($0.label).tag($0.value) }
                    }.labelsHidden()
                }
            case .path(let dirsOnly):
                let v = binding(f, "") { $0 as? String }
                labeled(f) {
                    HStack {
                        TextField("", text: v).textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            let p = NSOpenPanel()
                            p.canChooseDirectories = dirsOnly; p.canChooseFiles = !dirsOnly
                            if p.runModal() == .OK, let url = p.url { v.wrappedValue = url.path }
                        }
                    }
                }
            case .info:
                Text(f.title).font(.system(size: 13, weight: .medium))
            }
            if !f.help.isEmpty {
                Text(f.help).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labeled<C: View>(_ f: PluginSettingField, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(f.title).font(.system(size: 13, weight: .medium))
            content()
        }
    }
}

/// Hosts a plugin-supplied NSView.
struct PluginCustomViewHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
