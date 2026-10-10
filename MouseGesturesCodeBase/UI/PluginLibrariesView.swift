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
    @ObservedObject private var license = LicenseService.shared
    @Environment(\.dismiss) private var dismiss

    /// Called after anything installs/uninstalls so the host list can refresh.
    var onChange: () -> Void = {}
    /// True when shown as a Settings page rather than a sheet: no title bar buttons, no file install,
    /// no "Done", and the page scrolls with Settings instead of on its own.
    var embedded = false
    /// Handles a plugin file chosen via "Install from File…".
    var onInstallFile: (Result<[URL], Error>) -> Void = { _ in }

    @State private var message: String?
    @State private var messageIsError = false
    @State private var showingFilePicker = false
    @State private var settingsTarget: SettingsTarget?
    @State private var searchText = ""
    @State private var kindFilter: LibraryPluginKind?
    @State private var statusFilter: LibraryStatusFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            HStack {
                if !embedded { Text("Add Plugins").font(.title2.bold()) }
                Spacer()
                if !embedded {
                    Button { showingFilePicker = true } label: { Label("Install from File…", systemImage: "doc.badge.plus") }
                }
                Button { Task { await service.refreshAll() } } label: { Label("Check for Updates", systemImage: "arrow.clockwise") }
                    .disabled(service.isRefreshing)
                if service.updatesAvailableCount > 0, canInstall {
                    Button { updateAll() } label: { Label("Update All (\(service.updatesAvailableCount))", systemImage: "arrow.up.circle") }
                        .disabled(!service.busyPluginIds.isEmpty)
                }
                if !embedded { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }

            proBanner

            Text(embedded
                 ? "Plugins are native code that runs with MouseGestures' permissions — only install ones you trust."
                 : "Plugins are native code that runs with MouseGestures' permissions — only install ones you trust. More GitHub libraries can be connected under Developer Settings ▸ Plugin Sources.")
                .font(.caption).foregroundColor(.secondary)

            if service.pendingRestartCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.orange)
                    Text("\(service.pendingRestartCount) plugin\(service.pendingRestartCount == 1 ? "" : "s") will finish installing when MouseGestures restarts.")
                        .font(.caption)
                    Spacer()
                    Button("Restart Now") { service.restartApp() }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
            }

            if let message {
                Text(message).font(.caption).foregroundColor(messageIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            recommendedStrip

            filterBar

            listContainer {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                    ForEach(service.libraries) { repo in
                        if !isFiltering || !visibleEntries(repo).isEmpty { libraryCard(repo) }
                    }
                    if isFiltering && totalMatches == 0 && !service.isRefreshing {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").font(.title2).foregroundColor(.secondary)
                            Text("No plugins match your filters").font(.headline)
                            Button("Clear Filters") { searchText = ""; kindFilter = nil; statusFilter = .all }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, MGStyle.Spacing.xl)
                    }
                }
            }
        }
        .padding(embedded ? 0 : MGStyle.Spacing.xl)
        .frame(minWidth: embedded ? 0 : 760, minHeight: embedded ? 0 : 500)
        .onAppear { service.reconcile() }
        .task { await service.refreshAll() }
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [UTType(filenameExtension: "plugin") ?? .item, .bundle],
                      allowsMultipleSelection: false) { onInstallFile($0); onChange() }
        .sheet(item: $settingsTarget) { PluginSettingsSheet(pluginId: $0.id, pluginName: $0.name) }
    }

    /// Sheet: the list scrolls on its own. Settings page: the page scrolls, so no inner scroll view.
    @ViewBuilder private func listContainer<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if embedded { content() } else { ScrollView { content() } }
    }

    // MARK: Pro

    /// Browsing is free; installing and updating need Pro.
    private var canInstall: Bool { license.isPro }

    @ViewBuilder private var proBanner: some View {
        if !canInstall {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugins are a Pro feature").font(.system(size: 13, weight: .semibold))
                    Text("Browse everything for free. Installing and updating plugins needs MouseGestures Pro.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("See License Options") {
                    // `dismiss` closes the surrounding window when this page isn't a sheet, so only sheets call it.
                    if !embedded { dismiss() }
                    NotificationCenter.default.post(name: .openUpgradeTab, object: nil)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        }
    }

    // MARK: Recommended

    private var recommended: [(entry: LibraryPluginEntry, repo: LibraryRepo)] {
        guard let repo = service.libraries.first(where: { service.isOfficial($0) }),
              let plugins = service.manifests[repo.id]?.plugins else { return [] }
        let states = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, service.state(of: $0)) })
        return PluginLibraryLogic.recommendedToInstall(plugins, states: states).map { ($0, repo) }
    }

    @ViewBuilder private var recommendedStrip: some View {
        let items = recommended
        if !items.isEmpty && !isFiltering {
            MGContentCard {
                HStack(alignment: .top, spacing: MGStyle.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Recommended to start", systemImage: "star.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.accentColor)
                        Text(items.map { $0.entry.name }.joined(separator: " · ")).font(.caption)
                        Text("The most useful ones: new triggers, timers and schedules, and text tools. "
                             + "You'll see exactly what each can do before anything installs.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if service.busyPluginIds.isEmpty {
                        Button("Install \(items.count) Recommended") { installRecommended(items.map { $0.entry }) }
                            .buttonStyle(.borderedProminent).disabled(!canInstall)
                    } else { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private func installRecommended(_ entries: [LibraryPluginEntry]) {
        var seen = Set<String>(), steps: [PluginLibraryService.PlannedInstall] = []
        do {
            for entry in entries {
                for step in try service.plan(for: entry) where seen.insert(step.id).inserted { steps.append(step) }
            }
        } catch { show(error.localizedDescription, error: true); return }
        guard !steps.isEmpty else { return }
        run(steps, title: "Install \(steps.count) recommended plugin\(steps.count == 1 ? "" : "s")?", verb: "Install", focus: nil)
    }

    // MARK: Search & filters

    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty || kindFilter != nil || statusFilter != .all }

    private func visibleEntries(_ repo: LibraryRepo) -> [LibraryPluginEntry] {
        (service.manifests[repo.id]?.plugins ?? []).filter {
            PluginLibraryLogic.matches($0, state: service.state(of: $0), query: searchText, kind: kindFilter, status: statusFilter)
        }
    }

    private var totalMatches: Int { service.libraries.reduce(0) { $0 + visibleEntries($1).count } }

    private var filterBar: some View {
        HStack(spacing: MGStyle.Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search plugins", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Picker("Type", selection: $kindFilter) {
                Text("All Types").tag(LibraryPluginKind?.none)
                ForEach(LibraryPluginKind.allCases, id: \.self) { Text($0.label).tag(LibraryPluginKind?.some($0)) }
            }
            .labelsHidden().frame(width: 120)

            Picker("Status", selection: $statusFilter) {
                ForEach(LibraryStatusFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden().frame(width: 130)
        }
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
                    ForEach(visibleEntries(repo)) { entry in
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
        let tint: Color = entry.kind == .action ? .blue : .orange
        return HStack(alignment: .top, spacing: MGStyle.Spacing.lg) {
            Image(systemName: PluginSymbols.symbol(for: entry.id, fallback: entry.kind == .action ? "bolt.fill" : "hand.tap.fill"))
                .font(.system(size: 16)).foregroundColor(tint)
                .frame(width: 28, height: 28).background(tint.opacity(0.12)).cornerRadius(MGStyle.Corner.lg)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.system(size: 13, weight: .semibold))
                    Text("v\(entry.version)").font(.caption2).foregroundColor(.secondary)
                    Text(entry.kind.label)
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                        .background((entry.kind == .action ? Color.blue : Color.orange).opacity(0.2)).cornerRadius(6)
                }
                if let d = entry.description { Text(d).font(.caption).foregroundColor(.secondary) }
                switch state {
                case .installed:
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundColor(.green)
                case .updateAvailable(let installed, _):
                    Label("v\(installed) installed", systemImage: "arrow.up.circle.fill")
                        .font(.caption2).foregroundColor(.orange)
                default: EmptyView()
                }
                if let a = entry.author { Text("by \(a)").font(.caption2).foregroundColor(.secondary) }
                permissionLine(entry)
                dependencyLines(entry)
                if service.installed[entry.id]?.needsRestart == true {
                    Text("Restart MouseGestures to finish installing this version.").font(.caption2).foregroundColor(.orange)
                }
                if case .incompatible(let min) = state {
                    Text("Requires MouseGestures \(min) or newer.").font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
            // Fixed order — secondary actions left, primary right — so buttons
            // never shift position when the install state changes.
            if busy {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: MGStyle.Spacing.md) {
                    if extensions.hasSettingsUI(entry.id), state.isInstalled {
                        Button("Settings") { settingsTarget = SettingsTarget(id: entry.id, name: entry.name) }
                    }
                    switch state {
                    case .notInstalled:
                        Button { confirmAndInstall(entry, repo: repo, verb: "Install") } label: {
                            if canInstall { Text("Install") } else { Label("Install", systemImage: "lock.fill") }
                        }
                        .buttonStyle(.borderedProminent).disabled(!canInstall)
                        .help(canInstall ? "" : "Installing plugins needs Pro")
                    case .updateAvailable(_, let available):
                        Button("Remove", role: .destructive) { uninstall(entry) }
                        Button("Update to \(available)") { confirmAndInstall(entry, repo: repo, verb: "Update") }
                            .buttonStyle(.borderedProminent).disabled(!canInstall)
                    case .installed:
                        Button("Remove", role: .destructive) { uninstall(entry) }
                    case .incompatible:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: Permissions & dependencies

    @ViewBuilder private func permissionLine(_ entry: LibraryPluginEntry) -> some View {
        let perms = ((try? PluginLibraryLogic.parsePermissions(entry.permissions)) ?? []).map { $0.summary }
        Label(perms.isEmpty ? "No special permissions" : "Can: " + perms.joined(separator: " · "),
              systemImage: perms.isEmpty ? "lock.shield" : "lock.open")
            .font(.caption2).foregroundColor(perms.isEmpty ? .secondary : .orange)
    }

    @ViewBuilder private func dependencyLines(_ entry: LibraryPluginEntry) -> some View {
        let reqs = (entry.requires ?? []).compactMap { PluginLibraryLogic.parseRequirement($0) }
        if !reqs.isEmpty {
            let parts = reqs.map { r -> String in
                let name = service.entry(id: r.id)?.name ?? r.id
                let ok = service.installedVersion(of: r.id) != nil
                return ok ? "\(name) ✓" : "\(name) (will be installed)"
            }
            Label("Requires: " + parts.joined(separator: ", "), systemImage: "link").font(.caption2).foregroundColor(.secondary)
        }
        let by = service.installedDependents(of: entry.id)
        if service.installed[entry.id] != nil, !by.isEmpty {
            Label("Required by: " + by.joined(separator: ", "), systemImage: "link.badge.plus").font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: Actions

    private func permissionText(_ e: LibraryPluginEntry) -> String {
        let perms = ((try? PluginLibraryLogic.parsePermissions(e.permissions)) ?? []).map { "    • " + $0.summary }
        return perms.isEmpty ? "    No special permissions" : perms.joined(separator: "\n")
    }

    private func confirmAndInstall(_ entry: LibraryPluginEntry, repo: LibraryRepo, verb: String) {
        let steps: [PluginLibraryService.PlannedInstall]
        do { steps = try service.plan(for: entry) } catch { show(error.localizedDescription, error: true); return }
        run(steps, title: "\(verb) “\(entry.name)”?", verb: verb, focus: entry.name)
    }

    private func updateAll() {
        let steps: [PluginLibraryService.PlannedInstall]
        do { steps = try service.updateAllPlan() } catch { show(error.localizedDescription, error: true); return }
        guard !steps.isEmpty else { return }
        run(steps, title: "Update \(steps.count) plugin\(steps.count == 1 ? "" : "s")?", verb: "Update", focus: nil)
    }

    private func run(_ steps: [PluginLibraryService.PlannedInstall], title: String, verb: String, focus: String?) {
        let alert = NSAlert()
        alert.messageText = title
        let sources = Set(steps.map { $0.repo.displayName }).sorted().joined(separator: ", ")
        var info = "This downloads native code from \(sources) and runs it inside MouseGestures, with the same access to your Mac (including Accessibility). Only continue if you trust the library's author.\n"
        for step in steps {
            let tag = step.entry.name == focus || focus == nil ? "" : " (required)"
            info += "\n\(step.entry.name) \(step.entry.version)\(tag) asks to:\n\(permissionText(step.entry))\n"
        }
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await service.install(plan: steps)
                let done = steps.count == 1 ? steps[0].entry.name : "\(steps.count) plugins"
                let restart = service.pendingRestartCount > 0 ? " Restart to finish." : ""
                show("\(done) \(verb == "Update" ? "updated" : "installed").\(restart)", error: false)
            } catch { show(error.localizedDescription, error: true) }
            onChange()
        }
    }

    private func uninstall(_ entry: LibraryPluginEntry) {
        let by = service.installedDependents(of: entry.id)
        if !by.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remove “\(entry.name)”?"
            alert.informativeText = "\(by.joined(separator: ", ")) \(by.count == 1 ? "requires" : "require") it and may stop working."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Remove Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
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
            Text("GitHub repositories with a library.json. The official library is connected automatically; "
                 + "add others (owner/repo, owner/repo@branch, or a github.com URL) to browse their plugins under Add Plugins.")
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
