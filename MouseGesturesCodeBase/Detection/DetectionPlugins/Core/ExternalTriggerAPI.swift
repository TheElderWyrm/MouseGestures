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

    // Keep this layout and `ExternalTriggerHost`/`ExternalTriggerPlugin` unchanged: installed library plugins are
    // compiled binaries, and altering a struct or protocol they use crashes them. New capabilities go in the
    // separate protocols below, which plugins opt into.
    public init(id: String, name: String, summary: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// Adopt to let gestures override options for a trigger (sensitivity, timing…). An unset option means "use the
/// plugin's own setting", so the plugin resolves its own defaults.
public protocol ExternalTriggerOptionsProviding: AnyObject {
    func options(forTrigger id: String) -> [PluginSettingField]
}

/// The host object handed to `start` also conforms to this; cast to it to fire a specific binding.
public protocol ExternalTriggerBindingHost: ExternalTriggerHost {
    /// Like `fire(triggerId:)` but only runs gestures whose overrides match this binding.
    func fire(binding: ExternalTriggerBinding)
}

/// One gesture's use of a trigger, with the options that gesture overrides (absent key = plugin default).
/// Gestures with identical overrides share a binding, so a plugin evaluates each distinct configuration once.
public struct ExternalTriggerBinding {
    public let triggerId: String
    public let options: [String: Any]
    let key: String

    init(triggerId: String, overrides: [String: AnyCodable]?) {
        self.triggerId = triggerId
        let o = overrides ?? [:]
        options = o.mapValues { $0.value }
        key = triggerId + "|" + o.keys.sorted().map { "\($0)=\(o[$0]!.value)" }.joined(separator: ",")
    }

    public func number(_ k: String, default d: Double) -> Double { (options[k] as? NSNumber)?.doubleValue ?? d }
    public func string(_ k: String, default d: String) -> String { options[k] as? String ?? d }
    public func bool(_ k: String, default d: Bool) -> Bool { (options[k] as? NSNumber)?.boolValue ?? d }
}

/// Adopt (besides `ExternalTriggerPlugin`) to learn which triggers are in use and with which overrides. Called after
/// `start` and whenever gestures change; evaluate only these bindings and report them with `host.fire(binding:)`.
public protocol ExternalTriggerBindingAware: AnyObject {
    func bindingsChanged(_ bindings: [ExternalTriggerBinding])
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
final class ExternalTriggerAdapter: BaseDetectionPlugin, ExternalTriggerBindingHost {
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
    func options(forTrigger id: String) -> [PluginSettingField] {
        (external as? ExternalTriggerOptionsProviding)?.options(forTrigger: id) ?? []
    }

    override func start() throws {
        try super.start()
        reconcile()
    }

    override func stop() {
        if started { external.stop(); started = false }
        super.stop()
    }

    override func configurationChanged() {
        super.configurationChanged()
        reconcile()
    }

    // MARK: Run only while needed
    // A trigger plugin's event monitors and timers cost battery, so it runs only while at least one
    // enabled gesture uses one of its triggers (and, for library plugins, while the license allows it).

    private var hasBoundGestures: Bool {
        guard let gestures = context?.configuration.gestures else { return false }
        return gestures.contains { g in
            guard g.isEnabled, let trigger = g.components.externalTrigger, trigger.isEnabled else { return false }
            return trigger.pluginId == identifier
        }
    }

    private func reconcile() {
        guard state == .running else { return }
        let wanted = hasBoundGestures && PluginLibraryService.proGateAllows(pluginId: identifier)
        if wanted, !started {
            do {
                try external.start(host: self)
                started = true
            } catch {
                log("Could not start: \(error.localizedDescription)")
            }
        }
        if wanted, started { (external as? ExternalTriggerBindingAware)?.bindingsChanged(currentBindings()) }
        if !wanted, started {
            external.stop(); started = false
            log("Stopped (no gesture uses it)")
        }
    }

    private func currentBindings() -> [ExternalTriggerBinding] {
        var seen = Set<String>(), result: [ExternalTriggerBinding] = []
        for g in context?.configuration.gestures ?? [] where g.isEnabled {
            guard let t = g.components.externalTrigger, t.isEnabled, t.pluginId == identifier else { continue }
            let b = ExternalTriggerBinding(triggerId: t.triggerId, overrides: t.options)
            if seen.insert(b.key).inserted { result.append(b) }
        }
        return result
    }

    // MARK: ExternalTriggerHost

    var storageDirectory: URL {
        context?.storageDirectory ?? FileManager.default.temporaryDirectory
    }

    func log(_ message: String) {
        context?.logger.log(message, file: #file, function: #function, line: #line)
    }

    func fire(triggerId: String) { dispatch(triggerId: triggerId, bindingKey: nil) }
    func fire(binding: ExternalTriggerBinding) { dispatch(triggerId: binding.triggerId, bindingKey: binding.key) }

    private func dispatch(triggerId: String, bindingKey: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.started, self.shouldContinue(), let context = self.context,
                  PluginLibraryService.proGateAllows(pluginId: self.identifier) else { return }
            let matches = context.configuration.gestures.filter {
                guard $0.isEnabled, let t = $0.components.externalTrigger, t.isEnabled else { return false }
                guard t.pluginId == self.identifier && t.triggerId == triggerId else { return false }
                return bindingKey == nil || ExternalTriggerBinding(triggerId: triggerId, overrides: t.options).key == bindingKey
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
