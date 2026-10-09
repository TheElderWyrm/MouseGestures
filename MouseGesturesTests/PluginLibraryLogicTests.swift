import XCTest

final class PluginLibraryLogicTests: XCTestCase {

    private let goodSHA = String(repeating: "ab", count: 32)

    private func entry(id: String = "com.example.foo", version: String = "1.0.0", min: String? = nil,
                       download: String = "dist/foo.zip", sha: String? = nil) -> LibraryPluginEntry {
        LibraryPluginEntry(id: id, name: "Foo", kind: .action, version: version, minAppVersion: min,
                           download: download, sha256: sha ?? goodSHA)
    }

    // MARK: repo parsing

    func testParseRepoForms() throws {
        XCTAssertEqual(try PluginLibraryLogic.parseRepo("octo/lib"), LibraryRepo(owner: "octo", repo: "lib"))
        XCTAssertEqual(try PluginLibraryLogic.parseRepo("octo/lib@v2"), LibraryRepo(owner: "octo", repo: "lib", ref: "v2"))
        XCTAssertEqual(try PluginLibraryLogic.parseRepo("https://github.com/octo/lib.git"), LibraryRepo(owner: "octo", repo: "lib"))
        XCTAssertEqual(try PluginLibraryLogic.parseRepo(" https://github.com/octo/lib/tree/dev/x "),
                       LibraryRepo(owner: "octo", repo: "lib", ref: "dev/x"))
    }

    func testSubfolderLibraries() throws {
        let repo = try PluginLibraryLogic.parseRepo("octo/mono/Plugins")
        XCTAssertEqual(repo, LibraryRepo(owner: "octo", repo: "mono", subpath: "Plugins"))
        XCTAssertEqual(repo.id, "octo/mono/Plugins")
        XCTAssertEqual(PluginLibraryLogic.manifestURL(for: repo)?.absoluteString,
                       "https://raw.githubusercontent.com/octo/mono/HEAD/Plugins/library.json")
        let entry = LibraryPluginEntry(id: "a.b", name: "A", kind: .action, version: "1.0", download: "dist/a.zip", sha256: String(repeating: "0", count: 64))
        XCTAssertEqual(try PluginLibraryLogic.downloadURL(for: entry, in: repo).absoluteString,
                       "https://raw.githubusercontent.com/octo/mono/HEAD/Plugins/dist/a.zip")
        XCTAssertThrowsError(try PluginLibraryLogic.parseRepo("octo/mono/../x"))
        XCTAssertEqual(PluginLibraryLogic.officialRepo.subpath, "Plugins")
    }

    func testRecommendedToInstall() throws {
        func entry(_ id: String, rec: Bool?) -> LibraryPluginEntry {
            LibraryPluginEntry(id: id, name: id, kind: .action, version: "1.0", download: "d.zip",
                               sha256: String(repeating: "0", count: 64), recommended: rec)
        }
        let list = [entry("a", rec: true), entry("b", rec: nil), entry("c", rec: true), entry("d", rec: true), entry("e", rec: false)]
        let states: [String: LibraryInstallState] = ["a": .notInstalled, "c": .installed(version: "1.0"),
                                                      "d": .incompatible(minAppVersion: "9.0")]
        XCTAssertEqual(PluginLibraryLogic.recommendedToInstall(list, states: states).map { $0.id }, ["a"])
        // a manifest without the field still decodes
        let zeros = String(repeating: "0", count: 64)
        let json = #"{"id":"x.y","name":"X","kind":"action","version":"1.0","download":"d.zip","sha256":"\#(zeros)"}"#
        XCTAssertNil(try JSONDecoder().decode(LibraryPluginEntry.self, from: Data(json.utf8)).recommended)
    }

    func testSupersededPluginsAreRecognised() {
        XCTAssertTrue(PluginLibraryLogic.isSuperseded(bundleFileName: "com.mousegestures.lib.timers.plugin"))
        XCTAssertTrue(PluginLibraryLogic.isSuperseded(bundleFileName: "com.mousegestures.lib.texttools@2.1.0.plugin"))
        XCTAssertFalse(PluginLibraryLogic.isSuperseded(bundleFileName: "com.mousegestures.lib.clipboard.plugin"))
        XCTAssertFalse(PluginLibraryLogic.isSuperseded(bundleFileName: "com.mousegestures.lib.timersX.plugin"))
    }

    func testParseRepoRejectsGarbage() {
        for bad in ["", "octo", "a/b/../c", "a/b//c", "http://github.com/o/r", "https://evil.com/o/r", "-o/r", "o/r@..", "o/../x", "o/r@a b"] {
            XCTAssertThrowsError(try PluginLibraryLogic.parseRepo(bad), bad)
        }
    }

    // MARK: URLs

    func testManifestURLUsesHeadByDefault() {
        let url = PluginLibraryLogic.manifestURL(for: LibraryRepo(owner: "o", repo: "r"))
        XCTAssertEqual(url?.absoluteString, "https://raw.githubusercontent.com/o/r/HEAD/library.json")
        let pinned = PluginLibraryLogic.manifestURL(for: LibraryRepo(owner: "o", repo: "r", ref: "v1"))
        XCTAssertEqual(pinned?.absoluteString, "https://raw.githubusercontent.com/o/r/v1/library.json")
    }

    func testRelativePathTraversalRejected() {
        for bad in ["../x", "a/../b", "/abs", "a//b", "a\\b", "https://x", "a?b", ""] {
            XCTAssertFalse(PluginLibraryLogic.isSafeRelativePath(bad), bad)
        }
        XCTAssertTrue(PluginLibraryLogic.isSafeRelativePath("dist/foo-1.0.zip"))
    }

    func testDownloadURLResolution() throws {
        let repo = LibraryRepo(owner: "o", repo: "r")
        XCTAssertEqual(try PluginLibraryLogic.downloadURL(for: entry(), in: repo).absoluteString,
                       "https://raw.githubusercontent.com/o/r/HEAD/dist/foo.zip")
        let asset = entry(download: "https://github.com/o/r/releases/download/v1/foo.zip")
        XCTAssertNoThrow(try PluginLibraryLogic.downloadURL(for: asset, in: repo))
        for bad in ["http://github.com/o/r/a.zip", "https://evil.com/a.zip", "https://githubusercontent.com.evil.com/a.zip", "../a.zip"] {
            XCTAssertThrowsError(try PluginLibraryLogic.downloadURL(for: entry(download: bad), in: repo), bad)
        }
    }

    // MARK: manifest

    func testParseManifestRoundTrip() throws {
        let json = """
        {"schemaVersion":1,"name":"Lib","plugins":[{"id":"com.example.foo","name":"Foo","kind":"detection",
        "version":"1.2","download":"foo.zip","sha256":"\(goodSHA)"}]}
        """
        let m = try PluginLibraryLogic.parseManifest(Data(json.utf8))
        XCTAssertEqual(m.plugins.first?.kind, .detection)
    }

    func testManifestValidation() {
        func manifest(_ plugins: [LibraryPluginEntry], schema: Int = 1, name: String = "L") -> LibraryManifest {
            LibraryManifest(schemaVersion: schema, name: name, plugins: plugins)
        }
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([], schema: 2)))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([], name: " ")))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([entry(id: "../evil")])))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([entry(id: "a/b/c")])))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([entry(version: "1.x")])))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([entry(sha: "short")])))
        XCTAssertThrowsError(try PluginLibraryLogic.validate(manifest([entry(), entry()])))
        XCTAssertNoThrow(try PluginLibraryLogic.validate(manifest([entry(), entry(id: "com.example.bar")])))
        XCTAssertThrowsError(try PluginLibraryLogic.parseManifest(Data("nope".utf8)))
    }

    func testPermissionsParsing() throws {
        XCTAssertEqual(try PluginLibraryLogic.parsePermissions(nil), [])
        XCTAssertEqual(try PluginLibraryLogic.parsePermissions(["systemAPIs", "fileSystem"]), [.systemAPIs, .fileSystem])
        XCTAssertThrowsError(try PluginLibraryLogic.parsePermissions(["root"]))
        XCTAssertEqual(try PluginLibraryLogic.parsePermissions(["notifications"]), [.notifications])
        XCTAssertFalse(LibraryPermission.notifications.summary.isEmpty)
        let bad = LibraryManifest(schemaVersion: 1, name: "L", plugins: [
            LibraryPluginEntry(id: "com.example.foo", name: "Foo", kind: .action, version: "1.0",
                               download: "a.zip", sha256: goodSHA, permissions: ["everything"])])
        XCTAssertThrowsError(try PluginLibraryLogic.validate(bad))
    }

    func testOfficialRepoIsWellFormed() throws {
        let repo = PluginLibraryLogic.officialRepo
        XCTAssertEqual(try PluginLibraryLogic.parseRepo(repo.displayName), repo)
        XCTAssertEqual(PluginLibraryLogic.manifestURL(for: repo)?.host, "raw.githubusercontent.com")
    }

    func testChecksumCaseInsensitive() {
        XCTAssertTrue(PluginLibraryLogic.checksumMatches("ABCD", "abcd"))
        XCTAssertFalse(PluginLibraryLogic.checksumMatches("abcd", "abce"))
    }

    // MARK: state

    func testInstallState() {
        let e = entry(version: "1.2.0")
        XCTAssertEqual(PluginLibraryLogic.state(for: e, installedVersion: nil, appVersion: "1.0.1"), .notInstalled)
        XCTAssertEqual(PluginLibraryLogic.state(for: e, installedVersion: "1.2", appVersion: "1.0.1"), .installed(version: "1.2"))
        XCTAssertEqual(PluginLibraryLogic.state(for: e, installedVersion: "1.1.9", appVersion: "1.0.1"),
                       .updateAvailable(installed: "1.1.9", available: "1.2.0"))
    }

    func testIncompatibleWhenAppTooOld() {
        let e = entry(min: "2.0")
        XCTAssertEqual(PluginLibraryLogic.state(for: e, installedVersion: nil, appVersion: "1.0.1"), .incompatible(minAppVersion: "2.0"))
        XCTAssertEqual(PluginLibraryLogic.state(for: e, installedVersion: nil, appVersion: "2.0.0"), .notInstalled)
    }

    // MARK: search & filter

    func testSearchAndFilters() {
        let e = LibraryPluginEntry(id: "com.example.window", name: "Window Tiler", kind: .action, version: "1.0",
                                   author: "Ada", description: "Snap windows into a grid", download: "d.zip", sha256: goodSHA)
        let m = PluginLibraryLogic.matches
        XCTAssertTrue(m(e, .notInstalled, "", nil, .all))
        XCTAssertTrue(m(e, .notInstalled, "  tiler GRID ", nil, .all))   // every word, any field, any case
        XCTAssertTrue(m(e, .notInstalled, "ada", nil, .all))             // author
        XCTAssertFalse(m(e, .notInstalled, "tiler zebra", nil, .all))
        XCTAssertTrue(m(e, .notInstalled, "", .action, .all))
        XCTAssertFalse(m(e, .notInstalled, "", .detection, .all))
        XCTAssertTrue(m(e, .installed(version: "1.0"), "", nil, .installed))
        XCTAssertTrue(m(e, .updateAvailable(installed: "0.9", available: "1.0"), "", nil, .installed))
        XCTAssertTrue(m(e, .updateAvailable(installed: "0.9", available: "1.0"), "", nil, .updates))
        XCTAssertFalse(m(e, .installed(version: "1.0"), "", nil, .updates))
        XCTAssertTrue(m(e, .notInstalled, "", nil, .available))
        XCTAssertFalse(m(e, .installed(version: "1.0"), "", nil, .available))
    }

    // MARK: dependencies

    private func dep(_ id: String, version: String = "1.0", requires: [String]? = nil) -> LibraryPluginEntry {
        LibraryPluginEntry(id: id, name: id, kind: .action, version: version, download: "d.zip", sha256: goodSHA, requires: requires)
    }

    func testParseRequirement() {
        XCTAssertEqual(PluginLibraryLogic.parseRequirement("com.a.b"), .init(id: "com.a.b", minVersion: nil))
        XCTAssertEqual(PluginLibraryLogic.parseRequirement("com.a.b>=1.2"), .init(id: "com.a.b", minVersion: "1.2"))
        XCTAssertNil(PluginLibraryLogic.parseRequirement("com.a.b>=x"))
        XCTAssertNil(PluginLibraryLogic.parseRequirement("a"))
    }

    func testPlanOrdersDependenciesFirstAndSkipsSatisfied() throws {
        let a = dep("com.x.a"), b = dep("com.x.b", requires: ["com.x.a"]), c = dep("com.x.c", requires: ["com.x.b", "com.x.a>=1.0"])
        let cat = ["com.x.a": a, "com.x.b": b, "com.x.c": c]
        let plan = try PluginLibraryLogic.resolveInstallPlan(for: c, catalog: cat, installedVersions: [:], appVersion: "1.1")
        XCTAssertEqual(plan.map { $0.id }, ["com.x.a", "com.x.b", "com.x.c"])
        let partial = try PluginLibraryLogic.resolveInstallPlan(for: c, catalog: cat, installedVersions: ["com.x.a": "1.0"], appVersion: "1.1")
        XCTAssertEqual(partial.map { $0.id }, ["com.x.b", "com.x.c"])
    }

    func testPlanFailures() {
        let b = dep("com.x.b", requires: ["com.x.a"])
        XCTAssertThrowsError(try PluginLibraryLogic.resolveInstallPlan(for: b, catalog: [:], installedVersions: [:], appVersion: "1.1"))
        let needsNew = dep("com.x.n", requires: ["com.x.a>=2.0"])
        XCTAssertThrowsError(try PluginLibraryLogic.resolveInstallPlan(for: needsNew, catalog: ["com.x.a": dep("com.x.a")], installedVersions: [:], appVersion: "1.1"))
        // installed but too old, and the library has nothing newer
        XCTAssertThrowsError(try PluginLibraryLogic.resolveInstallPlan(for: needsNew, catalog: ["com.x.a": dep("com.x.a")], installedVersions: ["com.x.a": "1.0"], appVersion: "1.1"))
        let p = dep("com.x.p", requires: ["com.x.q"]), q = dep("com.x.q", requires: ["com.x.p"])
        XCTAssertThrowsError(try PluginLibraryLogic.resolveInstallPlan(for: p, catalog: ["com.x.p": p, "com.x.q": q], installedVersions: [:], appVersion: "1.1"))
    }

    func testDependentsAreTransitive() {
        let reqs = ["com.x.b": ["com.x.a"], "com.x.c": ["com.x.b>=1.0"], "com.x.d": []]
        XCTAssertEqual(PluginLibraryLogic.dependents(of: "com.x.a", requirements: reqs), ["com.x.b", "com.x.c"])
        XCTAssertEqual(PluginLibraryLogic.dependents(of: "com.x.c", requirements: reqs), [])
    }

    func testBundleFileNaming() {
        XCTAssertEqual(PluginLibraryLogic.bundleFileName(id: "com.x.a", version: "1.2"), "com.x.a@1.2.plugin")
        XCTAssertTrue(PluginLibraryLogic.isBundleFile("com.x.a@1.2.plugin", for: "com.x.a"))
        XCTAssertTrue(PluginLibraryLogic.isBundleFile("com.x.a.plugin", for: "com.x.a"))
        XCTAssertFalse(PluginLibraryLogic.isBundleFile("com.x.a-b@1.plugin", for: "com.x.a"))
    }
}
