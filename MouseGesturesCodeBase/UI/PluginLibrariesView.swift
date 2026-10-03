import SwiftUI
import AppKit

// MARK: - Plugin Libraries sheet
// Browse GitHub-hosted plugin libraries and install their action/detection plugins.

struct PluginLibrariesView: View {
    @ObservedObject private var service = PluginLibraryService.shared
    @Environment(\.dismiss) private var dismiss

    /// Called after anything installs/uninstalls so the host list can refresh.
    var onChange: () -> Void = {}

    @State private var newRepo = ""
    @State private var isAdding = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            HStack {
                Text("Plugin Libraries").font(.title2.bold())
                Spacer()
                Button { Task { await service.refreshAll() } } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(service.isRefreshing || service.libraries.isEmpty)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Text("A library is a GitHub repository with a library.json listing downloadable plugins. Plugins are native code that runs with MouseGestures' permissions — only add libraries you trust.")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                TextField("owner/repo, owner/repo@branch, or GitHub URL", text: $newRepo)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLibrary)
                Button(action: addLibrary) {
                    if isAdding { ProgressView().controlSize(.small) } else { Text("Add Library") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }

            if let message {
                Text(message).font(.caption).foregroundColor(messageIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                    if service.libraries.isEmpty {
                        Text("No libraries yet. Add a repository above to browse its plugins.")
                            .foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ForEach(service.libraries) { repo in libraryCard(repo) }
                }
            }
        }
        .padding(MGStyle.Spacing.xl)
        .frame(minWidth: 620, minHeight: 480)
        .onAppear { service.reconcile() }
        .task { if service.manifests.isEmpty { await service.refreshAll() } }
    }

    // MARK: Library card

    private func libraryCard(_ repo: LibraryRepo) -> some View {
        MGContentCard {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.manifests[repo.id]?.name ?? repo.displayName).font(.headline)
                        Text(repo.id).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Remove Library", role: .destructive) { service.removeLibrary(repo); onChange() }
                        .buttonStyle(.borderless).font(.caption)
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

    private func addLibrary() {
        let text = newRepo
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await service.addLibrary(text)
                newRepo = ""
                show("Library added.", error: false)
            } catch { show(error.localizedDescription, error: true) }
        }
    }

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
