import Foundation
import SwiftUI
import AppKit

/// Service for managing activation components and providing UI configuration
class ActivationComponentService {
    static let shared = ActivationComponentService()

    private init() {}

    /// Get all available component metadata from detection plugins
    func getAllComponentMetadata() -> [ActivationComponentUIMetadata] {
        let pluginManager = DetectionPluginManager.shared

        var allMetadata: [ActivationComponentUIMetadata] = []

        // Query each detection plugin for its component UI metadata
        // For now, return hardcoded metadata until plugins implement getComponentUIMetadata()
        // TODO: Update plugins to provide their own metadata

        return allMetadata
    }

    /// Get metadata for a specific activation type
    func getMetadata(for type: ActivationType) -> ActivationComponentUIMetadata? {
        return getAllComponentMetadata().first { $0.type == type }
    }

    /// Check if an activation type is available
    func isAvailable(_ type: ActivationType) -> Bool {
        return getMetadata(for: type) != nil
    }
}
