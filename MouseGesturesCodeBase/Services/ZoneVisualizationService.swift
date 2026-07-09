import Foundation
import AppKit

// MARK: - ZoneVisualizationService
// Single-purpose service for managing zone visualization settings

class ZoneVisualizationService {
    static let shared = ZoneVisualizationService()

    private let configuration = Configuration.shared

    private init() {}

    // MARK: - Zone Highlights

    func isShowZoneHighlights() -> Bool {
        return configuration.showZoneHighlights
    }

    func setShowZoneHighlights(_ show: Bool) {
        configuration.showZoneHighlights = show
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("zoneHighlightsChanged"),
            object: nil,
            userInfo: ["show": show]
        )
    }

    // MARK: - Zone Labels

    func isShowZoneLabels() -> Bool {
        return configuration.showZoneLabels
    }

    func setShowZoneLabels(_ show: Bool) {
        configuration.showZoneLabels = show
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("zoneLabelsChanged"),
            object: nil,
            userInfo: ["show": show]
        )
    }

    // MARK: - Zone Dimensions

    func getEdgeThreshold() -> CGFloat {
        return configuration.edgeThreshold
    }

    func setEdgeThreshold(_ threshold: CGFloat) {
        configuration.edgeThreshold = threshold
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("zoneDimensionsChanged"),
            object: nil
        )
    }

    func getCornerSize() -> CGFloat {
        return configuration.cornerSize
    }

    func setCornerSize(_ size: CGFloat) {
        configuration.cornerSize = size
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("zoneDimensionsChanged"),
            object: nil
        )
    }

    func getCornerBuffer() -> CGFloat {
        return configuration.cornerBuffer
    }

    func setCornerBuffer(_ buffer: CGFloat) {
        configuration.cornerBuffer = buffer
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("zoneDimensionsChanged"),
            object: nil
        )
    }

    func resetToDefaults() {
        setEdgeThreshold(30)
        setCornerSize(100)
        setCornerBuffer(50)

        log.log("Zone dimensions reset to defaults")
    }

    // MARK: - Hide All Highlights

    func hideAllHighlights() {
        // Send notification to hide all zone highlight windows
        NotificationCenter.default.post(
            name: Notification.Name("hideAllZoneHighlights"),
            object: nil
        )
    }
}
