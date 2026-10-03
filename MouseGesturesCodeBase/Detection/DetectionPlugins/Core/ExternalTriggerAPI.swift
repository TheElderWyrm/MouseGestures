import Foundation
import Cocoa

// MARK: - External Trigger Plugin SDK
// The public surface for third-party *detection* plugins (installed from plugin
// libraries). The built-in `DetectionPlugin` API is internal and tied to the
// gesture model, so external plugins instead declare named triggers ("shake",
// "wake") and call `host.fire(triggerId:)` when one happens. The app adapts them
// (`ExternalTriggerAdapter`) so any gesture can bind a trigger to an action.

public struct ExternalTriggerDefinition: Equatable {
    public let id: String
    public let name: String
    public let summary: String

    public init(id: String, name: String, summary: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// Handed to the plugin on `start`. Safe to call from any thread.
public protocol ExternalTriggerHost: AnyObject {
    /// Reports that a declared trigger just happened; runs every enabled gesture bound to it.
    func fire(triggerId: String)
    func log(_ message: String)
    /// A private folder for the plugin's own files.
    var storageDirectory: URL { get }
}

/// Principal class of an external detection plugin (must also subclass `NSObject`).
public protocol ExternalTriggerPlugin: AnyObject {
    var identifier: String { get }
    var name: String { get }
    var summary: String { get }
    var version: String { get }
    var author: String { get }
    /// SF Symbol shown in the gesture editor.
    var icon: String { get }
    var triggers: [ExternalTriggerDefinition] { get }

    /// Begin watching for events. Hold on to `host` to report them.
    func start(host: ExternalTriggerHost) throws
    func stop()
}

// MARK: - Adapter

/// Presents an `ExternalTriggerPlugin` to the app as an ordinary detection plugin.
final class ExternalTriggerAdapter: BaseDetectionPlugin, ExternalTriggerHost {
    let external: ExternalTriggerPlugin
    private var started = false

    init(_ external: ExternalTriggerPlugin) {
        self.external = external
        super.init()
    }

    override var identifier: String { external.identifier }
    override var name: String { external.name }
    override var description: String { external.summary }
    override var version: String { external.version }
    var author: String { external.author }
    override var triggerIcon: String { external.icon }
    override var triggerTitle: String { external.name }
    override var triggerDescription: String { external.summary }
    override var providesTriggerUI: Bool { true }
    var triggers: [ExternalTriggerDefinition] { external.triggers }

    override func start() throws {
        try super.start()
        guard !started else { return }
        try external.start(host: self)
        started = true
    }

    override func stop() {
        if started { external.stop(); started = false }
        super.stop()
    }

    // MARK: ExternalTriggerHost

    var storageDirectory: URL {
        context?.storageDirectory ?? FileManager.default.temporaryDirectory
    }

    func log(_ message: String) {
        context?.logger.log(message, file: #file, function: #function, line: #line)
    }

    func fire(triggerId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.started, self.shouldContinue(), let context = self.context else { return }
            let matches = context.configuration.gestures.filter {
                guard $0.isEnabled, let t = $0.components.externalTrigger, t.isEnabled else { return false }
                return t.pluginId == self.identifier && t.triggerId == triggerId
            }
            self.statistics = DetectionPluginStatistics(
                eventsDetected: self.statistics.eventsDetected + 1,
                gesturesTriggered: self.statistics.gesturesTriggered + matches.count)
            for gesture in matches {
                self.triggerGesture(gesture, context: GestureContext(source: .custom("\(self.identifier).\(triggerId)")))
            }
        }
    }
}
