import Foundation

// MARK: - Models

/// Which plugin system a library entry installs into.
public enum LibraryPluginKind: String, Codable, Equatable, CaseIterable {
    case action
    case detection
}

/// Capabilities a plugin may ask for. They're shown to the user at install time
/// and applied to the plugin's sandbox on load; anything not listed stays denied.
public enum LibraryPermission: String, CaseIterable, Codable {
    case systemAPIs, windowManager, fileSystem, executeActions, configuration

    public var summary: String {
        switch self {
        case .systemAPIs: return "Send keystrokes and run AppleScript"
        case .windowManager: return "Read and move windows"
        case .fileSystem: return "Read and write files in its own data folder"
        case .executeActions: return "Run other gesture actions"
        case .configuration: return "Read your MouseGestures configuration"
        }
    }
}

/// One installable plugin advertised by a library's `library.json`.
public struct LibraryPluginEntry: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kind: LibraryPluginKind
    public let version: String
    public let author: String?
    public let description: String?
    public let minAppVersion: String?
    /// Zip containing exactly one `.plugin`/`.bundle`. Either a path relative to
    /// the repository root, or an absolute https GitHub URL (e.g. a release asset).
    public let download: String
    /// Lowercase/uppercase hex SHA-256 of the zip.
    public let sha256: String
    /// Names from `LibraryPermission`. Action plugins are sandboxed to these; omit for none.
    public let permissions: [String]?

    public init(id: String, name: String, kind: LibraryPluginKind, version: String,
                author: String? = nil, description: String? = nil, minAppVersion: String? = nil,
                download: String, sha256: String, permissions: [String]? = nil) {
        self.permissions = permissions
        self.id = id; self.name = name; self.kind = kind; self.version = version
        self.author = author; self.description = description; self.minAppVersion = minAppVersion
        self.download = download; self.sha256 = sha256
    }
}

/// A library's manifest (`library.json` at the repository root).
public struct LibraryManifest: Codable, Equatable {
    public let schemaVersion: Int
    public let name: String
    public let description: String?
    public let plugins: [LibraryPluginEntry]

    public init(schemaVersion: Int, name: String, description: String? = nil, plugins: [LibraryPluginEntry]) {
        self.schemaVersion = schemaVersion; self.name = name
        self.description = description; self.plugins = plugins
    }
}

/// A GitHub repository the user has added as a plugin library.
public struct LibraryRepo: Codable, Equatable, Hashable, Identifiable {
    public let owner: String
    public let repo: String
    /// Branch, tag or commit. `nil` means the repository's default branch.
    public let ref: String?

    public init(owner: String, repo: String, ref: String? = nil) {
        self.owner = owner; self.repo = repo; self.ref = ref
    }

    public var id: String { ref.map { "\(owner)/\(repo)@\($0)" } ?? "\(owner)/\(repo)" }
    public var displayName: String { "\(owner)/\(repo)" }
}

/// What the app records after installing a plugin from a library.
public struct InstalledLibraryPlugin: Codable, Equatable {
    public let pluginId: String
    public let kind: LibraryPluginKind
    public let version: String
    public let libraryId: String
    /// `LibraryPermission` names granted at install time (applied when the plugin loads).
    public var grants: [String]?
    /// True when files are on disk but the code can't be (re)loaded until relaunch.
    public var needsRestart: Bool

    public init(pluginId: String, kind: LibraryPluginKind, version: String, libraryId: String,
                grants: [String]? = nil, needsRestart: Bool = false) {
        self.grants = grants
        self.pluginId = pluginId; self.kind = kind; self.version = version
        self.libraryId = libraryId; self.needsRestart = needsRestart
    }
}

public enum LibraryInstallState: Equatable {
    case notInstalled
    case installed(version: String)
    case updateAvailable(installed: String, available: String)
    case incompatible(minAppVersion: String)
}

public enum PluginLibraryError: Error, Equatable, LocalizedError {
    case invalidRepo(String)
    case invalidManifest(String)
    case unsupportedSchema(Int)
    case unsafeDownloadURL(String)
    case checksumMismatch
    case archiveTooLarge
    case archiveInvalid(String)
    case notSigned(String)
    case identifierMismatch(expected: String, found: String?)
    case loadFailed(String)
    case incompatible(String)
    case unknownPermission(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepo(let s): return "Not a valid GitHub repository: \(s)"
        case .invalidManifest(let s): return "Invalid library manifest: \(s)"
        case .unsupportedSchema(let v): return "Library uses manifest schema \(v), which this version of MouseGestures doesn't understand. Update the app."
        case .unsafeDownloadURL(let s): return "Refusing to download from \(s): only GitHub https URLs and repository paths are allowed."
        case .checksumMismatch: return "The downloaded file doesn't match the checksum in the library manifest, so it was discarded."
        case .archiveTooLarge: return "The plugin download is larger than the allowed size."
        case .archiveInvalid(let s): return "The plugin archive is invalid: \(s)"
        case .notSigned(let s): return "The plugin has no valid code signature (\(s)). It must at least be ad-hoc signed to load on Apple Silicon."
        case .identifierMismatch(let expected, let found):
            return "The plugin identified itself as \(found ?? "nothing") instead of \(expected), so it was removed."
        case .loadFailed(let s): return "The plugin was installed but failed to load: \(s)"
        case .incompatible(let v): return "This plugin requires MouseGestures \(v) or newer."
        case .unknownPermission(let p): return "The library asks for a permission this version doesn't know (\(p)). Update the app."
        }
    }
}

// MARK: - Logic

/// Pure rules for plugin libraries: repo references, manifest validation, URL
/// safety, checksum comparison and install-state. No networking, disk, or UI,
/// so it's fully unit-testable; `PluginLibraryService` wires it to the world.
public enum PluginLibraryLogic {

    /// The built-in source every install connects to automatically.
    public static let officialRepo = LibraryRepo(owner: "TheElderWyrm", repo: "MouseGestures-Plugins")

    public static let supportedSchemaVersion = 1
    public static let manifestFileName = "library.json"
    /// Hard cap on a plugin zip, to keep a hostile/broken repo from filling the disk.
    public static let maxArchiveBytes: Int64 = 50 * 1024 * 1024

    // MARK: Repo references

    /// Parses "owner/repo", "owner/repo@ref", or a github.com URL
    /// (optionally `/tree/<ref>`), with or without `.git`.
    public static func parseRepo(_ input: String) throws -> LibraryRepo {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PluginLibraryError.invalidRepo(input) }

        var ref: String?
        if text.lowercased().hasPrefix("http") {
            guard let url = URL(string: text), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com"
            else { throw PluginLibraryError.invalidRepo(input) }
            var parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 4, parts[2] == "tree" {
                ref = parts[3...].joined(separator: "/")
                parts = Array(parts[0..<2])
            }
            guard parts.count >= 2 else { throw PluginLibraryError.invalidRepo(input) }
            text = parts[0] + "/" + parts[1]
        } else if let at = text.firstIndex(of: "@") {
            ref = String(text[text.index(after: at)...])
            text = String(text[..<at])
        }

        if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, isValidOwner(parts[0]), isValidRepoName(parts[1]) else {
            throw PluginLibraryError.invalidRepo(input)
        }
        if let r = ref, !isValidRef(r) { throw PluginLibraryError.invalidRepo(input) }
        return LibraryRepo(owner: parts[0], repo: parts[1], ref: ref?.isEmpty == true ? nil : ref)
    }

    static func isValidOwner(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 39, !s.hasPrefix("-"), !s.hasSuffix("-") else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func isValidRepoName(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 100, s != ".", s != ".." else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    static func isValidRef(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 200, !s.contains(".."), !s.hasPrefix("/"), !s.hasSuffix("/") else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_./".contains($0)) }
    }

    // MARK: URLs

    public static func rawURL(for repo: LibraryRepo, path: String) -> URL? {
        guard isSafeRelativePath(path) else { return nil }
        let ref = repo.ref ?? "HEAD"
        let encoded = path.split(separator: "/").compactMap {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        }.joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/\(repo.owner)/\(repo.repo)/\(ref)/\(encoded)")
    }

    public static func manifestURL(for repo: LibraryRepo) -> URL? {
        rawURL(for: repo, path: manifestFileName)
    }

    /// Relative repo path: no leading slash, no `.`/`..` segments, no backslashes or schemes.
    public static func isSafeRelativePath(_ p: String) -> Bool {
        guard !p.isEmpty, !p.hasPrefix("/"), !p.contains("\\"), !p.contains(":"), !p.contains("?"), !p.contains("#") else { return false }
        return !p.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Resolves a manifest `download` field to a fetchable URL, or throws if it
    /// could point anywhere but GitHub.
    public static func downloadURL(for entry: LibraryPluginEntry, in repo: LibraryRepo) throws -> URL {
        let d = entry.download
        if d.lowercased().hasPrefix("http") {
            guard let url = URL(string: d), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), isAllowedDownloadHost(host)
            else { throw PluginLibraryError.unsafeDownloadURL(d) }
            return url
        }
        guard let url = rawURL(for: repo, path: d) else { throw PluginLibraryError.unsafeDownloadURL(d) }
        return url
    }

    public static func isAllowedDownloadHost(_ host: String) -> Bool {
        host == "github.com" || host == "raw.githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    // MARK: Manifest

    public static func parseManifest(_ data: Data) throws -> LibraryManifest {
        let manifest: LibraryManifest
        do { manifest = try JSONDecoder().decode(LibraryManifest.self, from: data) }
        catch { throw PluginLibraryError.invalidManifest(error.localizedDescription) }
        try validate(manifest)
        return manifest
    }

    public static func validate(_ m: LibraryManifest) throws {
        guard m.schemaVersion == supportedSchemaVersion else { throw PluginLibraryError.unsupportedSchema(m.schemaVersion) }
        guard !m.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PluginLibraryError.invalidManifest("missing name") }
        var seen = Set<String>()
        for p in m.plugins {
            guard isValidPluginId(p.id) else { throw PluginLibraryError.invalidManifest("bad plugin id '\(p.id)'") }
            guard seen.insert(p.id).inserted else { throw PluginLibraryError.invalidManifest("duplicate plugin id '\(p.id)'") }
            guard isValidVersion(p.version) else { throw PluginLibraryError.invalidManifest("bad version '\(p.version)' for \(p.id)") }
            if let min = p.minAppVersion, !isValidVersion(min) { throw PluginLibraryError.invalidManifest("bad minAppVersion for \(p.id)") }
            guard isValidSHA256(p.sha256) else { throw PluginLibraryError.invalidManifest("bad sha256 for \(p.id)") }
            _ = try parsePermissions(p.permissions)
            guard !p.name.isEmpty, !p.download.isEmpty else { throw PluginLibraryError.invalidManifest("incomplete entry \(p.id)") }
        }
    }

    public static func parsePermissions(_ raw: [String]?) throws -> [LibraryPermission] {
        try (raw ?? []).map {
            guard let p = LibraryPermission(rawValue: $0) else { throw PluginLibraryError.unknownPermission($0) }
            return p
        }
    }

    /// Reverse-DNS style. Also becomes a filename, so keep it tight.
    public static func isValidPluginId(_ s: String) -> Bool {
        guard s.count >= 3, s.count <= 128, !s.hasPrefix("."), !s.hasSuffix("."), !s.contains("..") else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    public static func isValidVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.count <= 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    public static func isValidSHA256(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    public static func checksumMatches(_ expected: String, _ actual: String) -> Bool {
        expected.lowercased() == actual.lowercased()
    }

    // MARK: State

    public static func state(for entry: LibraryPluginEntry, installedVersion: String?, appVersion: String) -> LibraryInstallState {
        if let min = entry.minAppVersion, UpdateLogic.isUpdateAvailable(current: appVersion, remote: min) {
            return .incompatible(minAppVersion: min)
        }
        guard let installed = installedVersion else { return .notInstalled }
        return UpdateLogic.isUpdateAvailable(current: installed, remote: entry.version)
            ? .updateAvailable(installed: installed, available: entry.version)
            : .installed(version: installed)
    }

    public static let bundleExtensions: Set<String> = ["plugin", "bundle"]
}
