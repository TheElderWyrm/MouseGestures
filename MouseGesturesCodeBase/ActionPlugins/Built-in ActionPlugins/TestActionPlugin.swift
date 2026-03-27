import Cocoa

// MARK: - Test Action Plugin
//
// A minimal action plugin that demonstrates the plugin interface and verifies
// the action plugin infrastructure is working. Provides two simple test actions.
//
// This plugin is also a reference template for building external action plugins.
// External bundles installed to:
//   ~/Library/Application Support/MouseGestures/Plugins/
// must expose a principal class (NSObject subclass) conforming to GestureActionPlugin.
//
// Build as a macOS Bundle target in Xcode:
//   - Product Type: Bundle
//   - Link against: the MouseGestures app (or a shared PluginKit framework)
//   - Principal Class: set in Info.plist

class TestActionPlugin: NSObject, GestureActionPlugin {

    // MARK: - Plugin Identity

    let identifier = "com.mousegestures.test.actions"
    let name = "Test Actions"
    override var description: String { "Developer test plugin — verifies action infrastructure" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.development
    let icon: NSImage? = nil

    // MARK: - Actions

    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "test_log",
            name: "Test: Log Message",
            description: "Writes a configurable message to the debug log",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "message",
                    name: "Message",
                    type: .string,
                    required: true,
                    defaultValue: AnyCodable("Hello from test plugin"),
                    description: "Text to write to the debug log"
                )
            ],
            icon: "text.bubble"
        ),
        PluginAction(
            id: "test_notify",
            name: "Test: Show Notification",
            description: "Shows a test notification to verify plugin execution",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "title",
                    name: "Title",
                    type: .string,
                    defaultValue: AnyCodable("Test Plugin"),
                    description: "Notification title"
                ),
                ParameterDefinition(
                    key: "message",
                    name: "Message",
                    type: .string,
                    defaultValue: AnyCodable("Action executed successfully"),
                    description: "Notification body"
                )
            ],
            icon: "bell.badge"
        )
    ]

    // MARK: - Lifecycle

    func initialize(context: PluginContext) throws {
        context.logger.log("TestActionPlugin: initialized", file: #file, function: #function, line: #line)
    }

    func cleanup() {}

    // MARK: - Execution

    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "test_log":
            let message = parameters.string(for: "message") ?? "(no message)"
            context.logger.log("TestActionPlugin [test_log]: \(message)", file: #file, function: #function, line: #line)

        case "test_notify":
            let title = parameters.string(for: "title") ?? "Test Plugin"
            let message = parameters.string(for: "message") ?? "Action executed successfully"
            context.showNotification(title: title, message: message, style: .info)

        default:
            throw PluginError.actionNotFound(action.id)
        }
    }

    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        return .valid
    }
}
