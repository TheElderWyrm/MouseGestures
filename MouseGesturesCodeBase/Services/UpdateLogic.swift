import Foundation

/// Remote update-feed payload (version.json).
public struct UpdateFeed: Codable, Equatable {
    public let version: String
    public let releaseNotes: String
    public let downloadURL: String
}

/// Pure, dependency-free update-comparison rules.
///
/// This is the single source of truth for version comparison and feed
/// parsing. It deliberately depends on nothing but `Foundation` (no
/// URLSession, UserDefaults, or UI), so it can be unit-tested in isolation.
/// `UpdateService` wires these rules to the network fetch and persisted state.
public enum UpdateLogic {

    /// Compares two dotted numeric version strings (e.g. "1.0.0" vs "1.1.0").
    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        return v1.compare(v2, options: .numeric)
    }

    /// True when `remote` is strictly newer than `current`.
    public static func isUpdateAvailable(current: String, remote: String) -> Bool {
        return compareVersions(current, remote) == .orderedAscending
    }

    /// Decodes a version.json payload from raw feed data.
    public static func parseFeed(_ data: Data) throws -> UpdateFeed {
        return try JSONDecoder().decode(UpdateFeed.self, from: data)
    }
}
