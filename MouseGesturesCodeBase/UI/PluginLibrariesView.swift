import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Plugins sheet
// One place to add plugins: browse the connected GitHub libraries (the official
// one is built in; more are added under Developer Settings), or install a plugin
// file from disk.

private struct SettingsTarget: Identifiable { let id: String; let name: String }

struct PluginLibrariesView: View {
    @ObservedObject private var service = PluginLibraryService.shared
    @ObservedObject private var extensions = PluginExtensionManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Called after anything installs/uninstalls so the host list can refresh.
    var onChange: () -> Void = {}
    /// Handles a plugin file chosen via "Install from File…".
    var onInstallFile: (Result<[URL], Error>) -> Void = { _ in }

    @State private var message: String?
    @State private var messageIsError = false
    @State private var showingFilePicker = false
    @State private var settingsTarget: SettingsTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            HStack {
                Text("Add Plugins").font(.title2.bold())
                Spacer()
                Button { showingFilePicker = true } label: { Label("Install from File…", systemImage: "doc.badge.plus") }
                Button { Task { await service.refreshAll() } } label: { Label("Check for Updates", systemImage: "arrow.clockwise") }
                    .disabled(service.isRefreshing)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Text("Plugins are native code that runs with MouseGestures' permissions — only install ones you trust. More GitHub libraries can be connected under Developer Settings ▸ Plugin Sources.")
                .font(.caption).foregroundColor(.secondary)

            if let message {
                Text(message).font(.caption).foregroundColor(messageIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                    ForEach(service.libraries) { repo in libraryCard(repo) }
                }
            }
        }
        .padding(MGStyle.Spacing.xl)
        .frame(minWidth: 640, minHeight: 500)
        .onAppear { service.reconcile() }
        .task { await service.refreshAll() }
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [UTType(filenameExtension: "plugin") ?? .item, .bundle],
                      allowsMultipleSelection: false) { onInstallFile($0); onChange() }
        .sheet(item: $settingsTarget) { PluginSettingsSheet(pluginId: $0.id, pluginName: $0.name) }
    }

    // MARK: Library card

    private func libraryCard(_ repo: LibraryRepo) -> some View {
        MGContentCard {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(service.manifests[repo.id]?.name ?? repo.displayName).font(.headline)
                            if service.isOfficial(repo) {
                                Text("OFFICIAL").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2)).cornerRadius(4)
                            }
                        }
                        Text(repo.id).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if service.isRefreshing && service.manifests[repo.id] == nil { ProgressView().controlSize(.small) }
                }
                if let desc = service.manifests[repo.id]?.description {
                    Text(desc).font(.caption).foregroundColor(.secondary)
                }
                if let err = service.loadErrors[repo.id] {
                    Text(err).font(.caption).foregroundColor(.red)
                }
                if let m = service.manifests[repo.id] {
                    if m.plugins.isEmpty { Text("This library lists no plugins.").font(.caption).foregroundColor(.secondary) }
                    ForEach(m.plugins) { entry in
                        Divider()
                        pluginRow(entry, repo: repo)
                    }
                }
            }
        }
    }

    private func pluginRow(_ entry: LibraryPluginEntry, repo: LibraryRepo) -> some View {
        let state = service.state(of: entry)
        let busy = service.busyPluginIds.contains(entry.id)
        return HStack(alignment: .top, spacing: MGStyle.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.system(size: 13, weight: .semibold))
                    Text("v\(entry.version)").font(.caption2).foregroundColor(.secondary)
                    Text(entry.kind == .action ? "Action" : "Detection")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                        .background((entry.kind == .action ? Color.blue : Color.orange).opacity(0.2)).cornerRadius(6)
                }
                if let d = entry.description { Text(d).font(.caption).foregroundColor(.secondary) }
                if let a = entry.author { Text("by \(a)").font(.caption2).foregroundColor(.secondary) }
                if service.installed[entry.id]?.needsRestart == true {
                    Text("Restart MouseGestures to finish updating.").font(.caption2).foregroundColor(.orange)
                }
                if case .incompatible(let min) = state {
                    Text("Requires MouseGestures \(min) or newer.").font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else {
                if extensions.hasSettingsUI(entry.id) {
                    Button("Settings") { settingsTarget = SettingsTarget(id: entry.id, name: entry.name) }
                }
                switch state {
                case .notInstalled:
                    Button("Install") { confirmAndInstall(entry, repo: repo, verb: "Install") }
                case .updateAvailable(_, let available):
                    Button("Update to \(available)") { confirmAndInstall(entry, repo: repo, verb: "Update") }
                    Button("Remove", role: .destructive) { uninstall(entry) }
                case .installed:
                    Text("Installed").font(.caption).foregroundColor(.secondary)
                    Button("Remove", role: .destructive) { uninstall(entry) }
                case .incompatible:
                    EmptyView()
                }
            }
        }
    }

    // MARK: Actions

    private func confirmAndInstall(_ entry: LibraryPluginEntry, repo: LibraryRepo, verb: String) {
        let alert = NSAlert()
        alert.messageText = "\(verb) “\(entry.name)”?"
        let perms = ((try? PluginLibraryLogic.parsePermissions(entry.permissions)) ?? []).map { "• " + $0.summary }
        let asks = perms.isEmpty ? "It asks for no special permissions." : "It asks to:\n" + perms.joined(separator: "\n")
        alert.informativeText = "This downloads native code from \(repo.displayName) and runs it inside MouseGestures, with the same access to your Mac (including Accessibility). Only continue if you trust the library's author.\n\n\(asks)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await service.install(entry, from: repo)
                show("\(entry.name) \(verb == "Update" ? "updated" : "installed").", error: false)
            } catch { show(error.localizedDescription, error: true) }
            onChange()
        }
    }

    private func uninstall(_ entry: LibraryPluginEntry) {
        do {
            try service.uninstall(pluginId: entry.id)
            show("\(entry.name) removed.", error: false)
        } catch { show(error.localizedDescription, error: true) }
        onChange()
    }

    private func show(_ text: String, error: Bool) { message = text; messageIsError = error }
}

// MARK: - Developer Settings ▸ Plugin Sources

/// Connect extra GitHub plugin libraries (the official one is always present).
struct PluginSourcesCard: View {
    @ObservedObject private var service = PluginLibraryService.shared
    @State private var newRepo = ""
    @State private var isAdding = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("Plugin Sources").font(.system(size: MGStyle.FontSize.body, weight: .medium))
            Text("GitHub repositories with a library.json. The official library is connected automatically; add others (owner/repo, owner/repo@branch, or a github.com URL) to browse their plugins under Add Plugins.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(service.libraries) { repo in
                HStack {
                    Image(systemName: service.isOfficial(repo) ? "checkmark.seal.fill" : "link").foregroundColor(.secondary)
                    Text(repo.id).font(.system(.caption, design: .monospaced))
                    if service.isOfficial(repo) { Text("official").font(.caption2).foregroundColor(.secondary) }
                    Spacer()
                    if !service.isOfficial(repo) {
                        Button("Remove", role: .destructive) { service.removeLibrary(repo) }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            HStack {
                TextField("owner/repo", text: $newRepo).textFieldStyle(.roundedBorder).onSubmit(add)
                Button(action: add) {
                    if isAdding { ProgressView().controlSize(.small) } else { Text("Connect") }
                }
                .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            if let message {
                Text(message).font(.caption).foregroundColor(messageIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func add() {
        let text = newRepo
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await service.addLibrary(text)
                newRepo = ""; message = "Connected."; messageIsError = false
            } catch { message = error.localizedDescription; messageIsError = true }
        }
    }
}
