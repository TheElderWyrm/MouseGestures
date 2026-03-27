import Foundation
import Cocoa

// MARK: - Test Detection Plugin
//
// A minimal detection plugin that demonstrates the plugin interface and
// verifies the detection infrastructure is working. Only active in developer
// mode; produces a debug log entry every 30 seconds when running.
//
// This plugin is also a reference template for building external detection
// plugins. External bundles installed to:
//   ~/Library/Application Support/MouseGestures/DetectionPlugins/
// must expose a principal class conforming to DetectionPlugin.

class TestDetectionPlugin: BaseDetectionPlugin {

    // MARK: - Plugin Identity

    override var identifier: String { "com.mousegestures.test.detection" }
    override var name: String { "Test Detection Plugin" }
    override var description: String { "Developer test plugin — verifies detection infrastructure" }
    override var version: String { "1.0.0" }
    override var priority: Int { 10 } // Low priority — runs after real plugins

    // Trigger UI metadata
    override var triggerIcon: String { "ladybug" }
    override var triggerTitle: String { "Test Trigger" }
    override var triggerDescription: String { "Dev trigger — logs when evaluated" }
    override var providesTriggerUI: Bool { true }

    override func configurationView() -> NSView? {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        let label = NSTextField(labelWithString: "Test Detection Plugin is active. Check debug log for heartbeat entries.")
        label.frame = NSRect(x: 10, y: 20, width: 280, height: 40)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        view.addSubview(label)
        return view
    }

    // MARK: - Internal State

    private var heartbeatTimer: Timer?
    private var eventCount = 0
    private var gestureFiredCount = 0

    // MARK: - Lifecycle

    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        context.logger.log("TestDetectionPlugin: initialized", file: #file, function: #function, line: #line)
    }

    override func start() throws {
        try super.start()
        scheduleHeartbeat()
        context?.logger.log("TestDetectionPlugin: started (heartbeat every 30s)", file: #file, function: #function, line: #line)
    }

    override func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        super.stop()
        context?.logger.log("TestDetectionPlugin: stopped (events=\(eventCount), gestures=\(gestureFiredCount))",
                            file: #file, function: #function, line: #line)
    }

    override func cleanup() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        super.cleanup()
    }

    // MARK: - Heartbeat

    private func scheduleHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.eventCount += 1
            self.context?.logger.log(
                "TestDetectionPlugin: heartbeat #\(self.eventCount) — gestures fired: \(self.gestureFiredCount)",
                file: #file, function: #function, line: #line
            )
        }
    }

    // MARK: - Statistics

    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: eventCount,
            gesturesTriggered: gestureFiredCount,
            errorsEncountered: 0
        )
    }
}
