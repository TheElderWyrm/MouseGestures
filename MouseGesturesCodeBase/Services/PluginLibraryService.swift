import Foundation
import CryptoKit
import AppKit

// MARK: - PluginLibraryService
// Plugin libraries are GitHub repositories with a `library.json` manifest that
// advertises prebuilt action/detection plugin bundles (see docs/PLUGIN_LIBRARIES.md).
// This service persists the user's libraries, fetches manifests, and runs the
// download -> checksum -> unzip -> signature -> install pipeline. All pure rules
// live in `PluginLibraryLogic`.

@MainActor
final class PluginLibraryService: ObservableObject {
    static let shared = PluginLibraryService()

    @Published private(set) var libraries: [LibraryRepo] = []
    @Published private(set) var manifests: [String: LibraryManifest] = [:]
    @Published private(set) var loadErrors: [String: String] = [:]
    @Published private(set) var installed: [String: InstalledLibraryPlugin] = [:]
    @Published private(set) var busyPluginIds: Set<String> = []
    @Published private(set) var isRefreshing = false

    private let directory: URL
    private var librariesFile: URL { directory.appendingPathComponent("libraries.json") }
    private var installedFile: URL { directory.appendingPathComponent("installed.json") }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 300
        return URLSession(configuration: c)
    }()

    private static let maxManifestBytes = 1_000_000

    /// Versions whose code is mapped into THIS process. Unloading can't unmap a bundle,
    /// so re-installing the same version is safe to load live; a different one isn't.
    private var residentVersions: [String: String] = [:]

    struct PlannedInstall: Identifiable {
        let entry: LibraryPluginEntry
        let repo: LibraryRepo
        var id: String { entry.id }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Grants recorded at install time, read straight from disk so the plugin
    /// loader can use them during app launch (before this service exists).
    // MARK: Pro gate
    // Plugins installed from a library are a Pro feature: they keep their files but stay inert
    // (no actions, no triggers) while the license isn't Pro, and wake up again the moment it is.

    private nonisolated static let gateLock = NSLock()
    private nonisolated(unsafe) static var gateCache: (stamp: Date, ids: Set<String>)?

    /// Ids of every plugin installed through a library, cached until `installed.json` changes.
    nonisolated static func libraryPluginIds() -> Set<String> {
        let file = Configuration.applicationSupportDirectory
            .appendingPathComponent("PluginLibraries", isDirectory: true).appendingPathComponent("installed.json")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
        gateLock.lock(); defer { gateLock.unlock() }
        if let c = gateCache, c.stamp == stamp { return c.ids }
        let ids = Set((read([InstalledLibraryPlugin].self, from: file) ?? []).map { $0.pluginId })
        gateCache = (stamp, ids)
        return ids
    }

    /// False for a library plugin when the license doesn't include Pro features.
    nonisolated static func proGateAllows(pluginId: String) -> Bool {
        LicenseService.shared.isPro || !libraryPluginIds().contains(pluginId)
    }

    nonisolated static func installedGrants(for pluginId: String) -> [String] {
        let file = Configuration.applicationSupportDirectory
            .appendingPathComponent("PluginLibraries", isDirectory: true).appendingPathComponent("installed.json")
        let records = read([InstalledLibraryPlugin].self, from: file) ?? []
        return records.first { $0.pluginId == pluginId }?.grants ?? []
    }

    private init() {
        directory = Configuration.applicationSupportDirectory.appendingPathComponent("PluginLibraries", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let custom = (Self.read([LibraryRepo].self, from: librariesFile) ?? []).filter { $0 != PluginLibraryLogic.officialRepo }
        libraries = [PluginLibraryLogic.officialRepo] + custom
        installed = Dictionary(uniqueKeysWithValues:
            (Self.read([InstalledLibraryPlugin].self, from: installedFile) ?? []).map { ($0.pluginId, $0) })
        // A fresh process has loaded whatever is on disk, so nothing is pending any more.
        for id in installed.keys { installed[id]?.needsRestart = false }
        residentVersions = installed.mapValues { $0.version }
    }

    // MARK: Persistence

    nonisolated private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        // The official source is built in; only user-added sources are persisted.
        if let d = try? enc.encode(libraries.filter { !isOfficial($0) }) { try? d.write(to: librariesFile, options: .atomic) }
        if let d = try? enc.encode(Array(installed.values)) { try? d.write(to: installedFile, options: .atomic) }
    }

    // MARK: Libraries

    /// Adds a library after confirming its manifest loads and validates.
    func addLibrary(_ input: String) async throws {
        let repo = try PluginLibraryLogic.parseRepo(input)
        guard !libraries.contains(repo) else { return }
        manifests[repo.id] = try await fetchManifest(repo)
        loadErrors[repo.id] = nil
        libraries.append(repo)
        save()
    }

    func isOfficial(_ repo: LibraryRepo) -> Bool { repo == PluginLibraryLogic.officialRepo }

    func removeLibrary(_ repo: LibraryRepo) {
        guard !isOfficial(repo) else { return }
        libraries.removeAll { $0 == repo }
        manifests[repo.id] = nil
        loadErrors[repo.id] = nil
        save()
    }

    /// Re-fetches every library's manifest. A failing library records its
    /// error and doesn't stop the others.
    func refreshAll() async {
        reconcile()
        isRefreshing = true
        defer { isRefreshing = false }
        for repo in libraries {
            do {
                manifests[repo.id] = try await fetchManifest(repo)
                loadErrors[repo.id] = nil
            } catch {
                loadErrors[repo.id] = error.localizedDescription
            }
        }
    }

    private func fetchManifest(_ repo: LibraryRepo) async throws -> LibraryManifest {
        guard let url = PluginLibraryLogic.manifestURL(for: repo) else { throw PluginLibraryError.invalidRepo(repo.id) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PluginLibraryError.invalidManifest(
                http.statusCode == 404 ? "\(repo.displayName) has no \(PluginLibraryLogic.manifestFileName) at its root (or the repo is private)"
                                       : "HTTP \(http.statusCode)")
        }
        guard data.count <= Self.maxManifestBytes else { throw PluginLibraryError.invalidManifest("manifest too large") }
        return try PluginLibraryLogic.parseManifest(data)
    }

    /// Forgets install records whose plugin is neither loaded nor on disk
    /// (e.g. the user deleted it, or removed it from the Plugin Management list).
    func reconcile() {
        let fm = FileManager.default
        let stale = installed.values.filter { rec in
            let loaded = rec.kind == .action ? PluginManager.shared.getPlugin(identifier: rec.pluginId) != nil
                                             : DetectionPluginManager.shared.isExternalPlugin(identifier: rec.pluginId)
            let onDisk = !bundleFiles(for: rec.pluginId, kind: rec.kind).isEmpty
            return !loaded && !onDisk
        }
        guard !stale.isEmpty else { return }
        for rec in stale { installed[rec.pluginId] = nil }
        save()
    }

    // MARK: Queries

    var pendingRestartCount: Int { installed.values.filter { $0.needsRestart }.count }

    /// id -> (entry, library) across all connected libraries; earlier libraries win.
    private var catalog: [String: PlannedInstall] {
        var result: [String: PlannedInstall] = [:]
        for repo in libraries {
            for e in manifests[repo.id]?.plugins ?? [] where result[e.id] == nil { result[e.id] = PlannedInstall(entry: e, repo: repo) }
        }
        return result
    }

    func entry(id: String) -> LibraryPluginEntry? { catalog[id]?.entry }

    /// What installing `entry` involves: its missing dependencies first, then itself.
    func plan(for entry: LibraryPluginEntry) throws -> [PlannedInstall] {
        let cat = catalog
        let steps = try PluginLibraryLogic.resolveInstallPlan(
            for: entry, catalog: cat.mapValues { $0.entry },
            installedVersions: installed.mapValues { $0.version }, appVersion: appVersion)
        return steps.compactMap { step in cat[step.id] }
    }

    /// Every available update (plus any dependencies they newly need), deduplicated and ordered.
    func updateAllPlan() throws -> [PlannedInstall] {
        var seen = Set<String>(), result: [PlannedInstall] = []
        for item in catalog.values.sorted(by: { $0.entry.name < $1.entry.name }) {
            guard case .updateAvailable = state(of: item.entry) else { continue }
            for step in try plan(for: item.entry) where seen.insert(step.id).inserted { result.append(step) }
        }
        return result
    }

    /// Names of installed plugins that require `pluginId` (directly or indirectly).
    func installedDependents(of pluginId: String) -> [String] {
        let reqs = installed.compactMapValues { $0.requires }
        return PluginLibraryLogic.dependents(of: pluginId, requirements: reqs)
            .map { entry(id: $0)?.name ?? $0 }
    }

    /// Relaunches the app so staged plugin updates load.
    func restartApp() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open '\(path)'"]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func bundleFiles(for pluginId: String, kind: LibraryPluginKind) -> [URL] {
        let dir = installDirectory(for: kind)
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { PluginLibraryLogic.isBundleFile($0.lastPathComponent, for: pluginId) }
    }

    nonisolated private static func principalClassName(of bundle: URL) -> String? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let d = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return nil }
        return dict["NSPrincipalClass"] as? String
    }

    func installedVersion(of pluginId: String) -> String? { installed[pluginId]?.version }

    func state(of entry: LibraryPluginEntry) -> LibraryInstallState {
        PluginLibraryLogic.state(for: entry, installedVersion: installed[entry.id]?.version, appVersion: appVersion)
    }

    var updatesAvailableCount: Int {
        manifests.values.flatMap { $0.plugins }.filter {
            if case .updateAvailable = state(of: $0) { return true } else { return false }
        }.count
    }

    private func isLoaded(_ entry: LibraryPluginEntry) -> Bool {
        switch entry.kind {
        case .action: return PluginManager.shared.getPlugin(identifier: entry.id) != nil
        case .detection: return DetectionPluginManager.shared.isExternalPlugin(identifier: entry.id)
        }
    }

    private func installDirectory(for kind: LibraryPluginKind) -> URL {
        kind == .action ? PluginManager.shared.userPluginsDirectoryURL : DetectionPluginManager.shared.externalPluginsDirectory
    }

    // MARK: Install / uninstall

    func install(_ entry: LibraryPluginEntry, from repo: LibraryRepo) async throws {
        guard !busyPluginIds.contains(entry.id) else { return }
        busyPluginIds.insert(entry.id)
        defer { busyPluginIds.remove(entry.id) }

        if case .incompatible(let min) = state(of: entry) { throw PluginLibraryError.incompatible(min) }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. Download + verify checksum BEFORE anything is unpacked.
        let url = try PluginLibraryLogic.downloadURL(for: entry, in: repo)
        let (tmp, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PluginLibraryError.archiveInvalid("download failed (HTTP \(http.statusCode))")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
        guard size > 0, size <= PluginLibraryLogic.maxArchiveBytes else { throw PluginLibraryError.archiveTooLarge }
        let digest = SHA256.hash(data: try Data(contentsOf: tmp, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard PluginLibraryLogic.checksumMatches(entry.sha256, digest) else { throw PluginLibraryError.checksumMismatch }

        // 2. Unpack, confirm nothing escaped, find the bundle, check its signature.
        let zip = work.appendingPathComponent("plugin.zip")
        try FileManager.default.moveItem(at: tmp, to: zip)
        let extracted = work.appendingPathComponent("x", isDirectory: true)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path], failure: PluginLibraryError.archiveInvalid("could not unzip"))
        let bundle = try Self.locateBundle(in: extracted)
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path],
                               failure: PluginLibraryError.notSigned("codesign --verify failed"))
        }

        // 3. Name the bundle after its id AND version: an update must land at a new path,
        // because macOS caches loaded bundles by path (a same-path reload runs the old code).
        let fileName = PluginLibraryLogic.bundleFileName(id: entry.id, version: entry.version)
        let staged = work.appendingPathComponent(fileName, isDirectory: true)
        try FileManager.default.moveItem(at: bundle, to: staged)

        // 4. Decide whether the new code can go live now. Loaded code can't be unmapped, so a
        // bundle whose principal class name is already registered would silently run the OLD
        // class. A new class name (the official library suffixes it per version) is safe to
        // swap in live; anything else stages for the next launch.
        let wasLoaded = isLoaded(entry)
        let className = Self.principalClassName(of: staged)
        let collides = className.map { NSClassFromString($0) != nil } ?? true
        let canLoadNow = !collides || (!wasLoaded && residentVersions[entry.id] == entry.version)
        let hotSwap = wasLoaded && canLoadNow

        // The permission grant must be on disk BEFORE the plugin loads (the loader reads it).
        let previous = installed[entry.id]
        let grants = try PluginLibraryLogic.parsePermissions(entry.permissions).map { $0.rawValue }
        installed[entry.id] = InstalledLibraryPlugin(pluginId: entry.id, kind: entry.kind, version: entry.version,
                                                     libraryId: repo.id, grants: grants, needsRestart: !canLoadNow,
                                                     requires: entry.requires)
        save()
        func rollback() { installed[entry.id] = hotSwap ? nil : previous; save() }

        // Remove superseded files so only the new version loads at next launch. A loaded
        // bundle's file may be deleted safely; its code stays mapped until relaunch.
        if hotSwap { try? uninstallLoaded(id: entry.id, kind: entry.kind) }
        let before = loadedIdentifiers(entry.kind)
        for old in bundleFiles(for: entry.id, kind: entry.kind) { try? FileManager.default.removeItem(at: old) }

        do {
            switch entry.kind {
            case .action: try PluginManager.shared.installPlugin(from: staged, loadNow: canLoadNow)
            case .detection: try DetectionPluginManager.shared.installExternalPlugin(from: staged, loadNow: canLoadNow)
            }
        } catch { rollback(); throw error }

        // 5. A freshly loaded plugin must be exactly the one the manifest promised.
        if canLoadNow {
            let added = loadedIdentifiers(entry.kind).subtracting(before)
            guard added == [entry.id] else {
                for id in added { try? uninstallLoaded(id: id, kind: entry.kind) }
                for f in bundleFiles(for: entry.id, kind: entry.kind) { try? FileManager.default.removeItem(at: f) }
                rollback()
                if added.isEmpty { throw PluginLibraryError.loadFailed("see the log for details") }
                throw PluginLibraryError.identifierMismatch(expected: entry.id, found: added.first)
            }
            residentVersions[entry.id] = entry.version
        }

        save()
        log.log("PluginLibrary: installed \(entry.id) \(entry.version) from \(repo.id)\(canLoadNow ? "" : " (restart required)")")
    }

    /// Installs a plan in order (dependencies first), stopping at the first failure.
    func install(plan: [PlannedInstall]) async throws {
        for step in plan { try await install(step.entry, from: step.repo) }
    }

    func uninstall(pluginId: String) throws {
        guard let record = installed[pluginId] else { return }
        let loaded = record.kind == .action ? PluginManager.shared.getPlugin(identifier: pluginId) != nil
                                            : DetectionPluginManager.shared.isExternalPlugin(identifier: pluginId)
        if loaded {
            do { try uninstallLoaded(id: pluginId, kind: record.kind) }
            // A staged update already deleted the loaded bundle's file; that's fine.
            catch let e as CocoaError where e.code == .fileNoSuchFile {}
        }
        for f in bundleFiles(for: pluginId, kind: record.kind) { try FileManager.default.removeItem(at: f) }
        installed[pluginId] = nil
        PluginSettingsStore.shared.removeAll(pluginId)
        save()
        log.log("PluginLibrary: uninstalled \(pluginId)")
    }

    // MARK: Helpers

    private func loadedIdentifiers(_ kind: LibraryPluginKind) -> Set<String> {
        switch kind {
        case .action: return Set(PluginManager.shared.getAllPlugins().map { $0.identifier })
        case .detection: return Set(DetectionPluginManager.shared.getAllPlugins().map { $0.identifier })
        }
    }

    private func uninstallLoaded(id: String, kind: LibraryPluginKind) throws {
        switch kind {
        case .action: try PluginManager.shared.uninstallPlugin(identifier: id)
        case .detection: try DetectionPluginManager.shared.uninstallExternalPlugin(identifier: id)
        }
    }

    /// Exactly one `.plugin`/`.bundle` at the archive's top level, and no
    /// symlink anywhere in the tree that resolves outside it.
    nonisolated static func locateBundle(in root: URL) throws -> URL {
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().path
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw PluginLibraryError.archiveInvalid("empty archive")
        }
        for case let item as URL in walker {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                let target = item.resolvingSymlinksInPath().path
                guard target == rootPath || target.hasPrefix(rootPath + "/") else {
                    throw PluginLibraryError.archiveInvalid("symlink escapes the archive")
                }
            }
        }
        let top = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { PluginLibraryLogic.bundleExtensions.contains($0.pathExtension.lowercased()) }
        guard top.count == 1 else {
            throw PluginLibraryError.archiveInvalid(top.isEmpty ? "no .plugin bundle at the top level" : "more than one bundle")
        }
        return top[0]
    }

    nonisolated private static func run(_ tool: String, _ args: [String], failure: PluginLibraryError) async throws {
        let status: Int32 = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = args
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); cont.resume(returning: p.terminationStatus) }
                catch { cont.resume(returning: -1) }
            }
        }
        guard status == 0 else { throw failure }
    }
}
