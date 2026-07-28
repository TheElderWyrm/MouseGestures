import Foundation

/// A single asset attached to a GitHub release (subset of the API's fields).
public struct GitHubReleaseAsset: Codable, Equatable {
    public let name: String
    public let browserDownloadURL: String
    public let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }

    public init(name: String, browserDownloadURL: String, size: Int64) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
    }
}

/// Subset of GitHub's `GET /repos/{owner}/{repo}/releases/latest` response
/// that MouseGestures' update check actually needs.
public struct GitHubRelease: Codable, Equatable {
    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let body: String?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, body, assets
    }

    public init(tagName: String, draft: Bool, prerelease: Bool, body: String?, assets: [GitHubReleaseAsset]) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.body = body
        self.assets = assets
    }
}

/// Pure, dependency-free update-comparison and GitHub-release-parsing rules.
///
/// This is the single source of truth for version comparison and release
/// selection. It deliberately depends on nothing but `Foundation` (no
/// URLSession, UserDefaults, or UI), so it can be unit-tested in isolation.
/// `UpdateService` wires these rules to the network fetch and persisted state.
///
/// The update check pulls directly from GitHub's live "latest release" API
/// rather than a hand-maintained `version.json` -- there's nothing to forget
/// to update after cutting a release, and the app can never point at a DMG
/// that doesn't match what was actually published. This mirrors the same
/// approach the marketing site's own release lookup already uses
/// (`Website/js/main.js`'s `checkRelease()`).
public enum UpdateLogic {

    /// Compares two dotted numeric version strings (e.g. "1.0.0" vs "1.1.0").
    ///
    /// Component-count tolerant: shorter version strings are zero-padded to
    /// match the longer one before comparing, so "1.0" and "1.0.0" compare
    /// as equal instead of "1.0" < "1.0.0" (which `.numeric` string
    /// comparison would otherwise report, since it compares lexically once
    /// the shared prefix is exhausted).
    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".", omittingEmptySubsequences: false)
        let parts2 = v2.split(separator: ".", omittingEmptySubsequences: false)
        let count = max(parts1.count, parts2.count)
        let padded1 = (parts1 + Array(repeating: Substring("0"), count: count - parts1.count)).joined(separator: ".")
        let padded2 = (parts2 + Array(repeating: Substring("0"), count: count - parts2.count)).joined(separator: ".")
        return padded1.compare(padded2, options: .numeric)
    }

    /// True when `remote` is strictly newer than `current`.
    public static func isUpdateAvailable(current: String, remote: String) -> Bool {
        return compareVersions(current, remote) == .orderedAscending
    }

    /// Decodes a GitHub "get latest release" API response.
    public static func parseGitHubRelease(_ data: Data) throws -> GitHubRelease {
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// A release is only offered as an update if it's a real, published
    /// release -- not a draft or a prerelease.
    public static func isEligible(_ release: GitHubRelease) -> Bool {
        return !release.draft && !release.prerelease
    }

    /// Strips a leading "v" from a tag name ("v1.2.3" -> "1.2.3").
    public static func versionString(fromTag tagName: String) -> String {
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Picks the release's macOS disk image, if it has one.
    public static func downloadAsset(from release: GitHubRelease) -> GitHubReleaseAsset? {
        return release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}
