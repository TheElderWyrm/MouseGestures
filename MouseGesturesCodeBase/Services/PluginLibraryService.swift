import Foundation
import CryptoKit

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

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private init() {
        directory = Configuration.applicationSupportDirectory.appendingPathComponent("PluginLibraries", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        libraries = Self.read([LibraryRepo].self, from: librariesFile) ?? []
        installed = Dictionary(uniqueKeysWithValues:
            (Self.read([InstalledLibraryPlugin].self, from: installedFile) ?? []).map { ($0.pluginId, $0) })
    }

    // MARK: Persistence

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(libraries) { try? d.write(to: librariesFile, options: .atomic) }
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

    func removeLibrary(_ repo: LibraryRepo) {
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
            let onDisk = fm.fileExists(atPath: installDirectory(for: rec.kind).appendingPathComponent("\(rec.pluginId).plugin").path)
            return !loaded && !onDisk
        }
        guard !stale.isEmpty else { return }
        for rec in stale { installed[rec.pluginId] = nil }
        save()
    }

    // MARK: Queries

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

        // 3. Name the bundle after its id (filename = identity on disk).
        let staged = work.appendingPathComponent("\(entry.id).plugin", isDirectory: true)
        try FileManager.default.moveItem(at: bundle, to: staged)

        // 4. Install. An already-loaded bundle can't be swapped in-process, so updates stage on disk.
        let wasLoaded = isLoaded(entry)
        let before = loadedIdentifiers(entry.kind)
        var needsRestart = wasLoaded
        switch entry.kind {
        case .action: try PluginManager.shared.installPlugin(from: staged, loadNow: !wasLoaded)
        case .detection: try DetectionPluginManager.shared.installExternalPlugin(from: staged, loadNow: !wasLoaded)
        }

        // 5. A freshly loaded plugin must be exactly the one the manifest promised.
        if !wasLoaded {
            let added = loadedIdentifiers(entry.kind).subtracting(before)
            guard added == [entry.id] else {
                for id in added { try? uninstallLoaded(id: id, kind: entry.kind) }
                try? FileManager.default.removeItem(at: installDirectory(for: entry.kind).appendingPathComponent("\(entry.id).plugin"))
                if added.isEmpty { throw PluginLibraryError.loadFailed("see the log for details") }
                throw PluginLibraryError.identifierMismatch(expected: entry.id, found: added.first)
            }
            needsRestart = false
        }

        installed[entry.id] = InstalledLibraryPlugin(pluginId: entry.id, kind: entry.kind, version: entry.version,
                                                     libraryId: repo.id, needsRestart: needsRestart)
        save()
        log.log("PluginLibrary: installed \(entry.id) \(entry.version) from \(repo.id)\(needsRestart ? " (restart required)" : "")")
    }

    func uninstall(pluginId: String) throws {
        guard let record = installed[pluginId] else { return }
        let file = installDirectory(for: record.kind).appendingPathComponent("\(pluginId).plugin")
        let loaded = record.kind == .action ? PluginManager.shared.getPlugin(identifier: pluginId) != nil
                                            : DetectionPluginManager.shared.isExternalPlugin(identifier: pluginId)
        if loaded {
            try uninstallLoaded(id: pluginId, kind: record.kind)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        installed[pluginId] = nil
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
