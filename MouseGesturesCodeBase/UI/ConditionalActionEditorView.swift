import SwiftUI
import AppKit

// MARK: - Conditional Action Editor

struct ConditionalActionEditorView: View {

    // Callbacks — no @Environment(\.dismiss); parent calls dismisser.end()
    let onSave: ([String: AnyCodable], String, [String: AnyCodable], String, [String: AnyCodable]) -> Void
    let onCancel: () -> Void

    // Condition state
    @State private var conditionType: String
    @State private var conditionNegate: Bool
    @State private var conditionApp: String
    @State private var conditionWindowTitle: String
    @State private var conditionProfile: String

    // True branch
    @State private var trueActionId: String
    @State private var trueActionParams: [String: AnyCodable]

    // False branch
    @State private var falseActionId: String
    @State private var falseActionParams: [String: AnyCodable]

    init(
        initialParameters: [String: AnyCodable],
        trueActionId: String,
        trueActionParams: [String: AnyCodable],
        falseActionId: String,
        falseActionParams: [String: AnyCodable],
        onSave: @escaping ([String: AnyCodable], String, [String: AnyCodable], String, [String: AnyCodable]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _conditionType        = State(initialValue: initialParameters["condition_type"]?.value as? String ?? "app_frontmost")
        _conditionNegate      = State(initialValue: initialParameters["condition_negate"]?.value as? Bool ?? false)
        _conditionApp         = State(initialValue: initialParameters["condition_app"]?.value as? String ?? "")
        _conditionWindowTitle = State(initialValue: initialParameters["condition_window_title"]?.value as? String ?? "")
        _conditionProfile     = State(initialValue: initialParameters["condition_profile"]?.value as? String ?? "")
        _trueActionId         = State(initialValue: trueActionId)
        _trueActionParams     = State(initialValue: trueActionParams)
        _falseActionId        = State(initialValue: falseActionId)
        _falseActionParams    = State(initialValue: falseActionParams)
        self.onSave   = onSave
        self.onCancel = onCancel
    }

    private let conditionOptions: [(id: String, label: String)] = [
        ("always", "Always"),
        ("app_frontmost", "App Is Frontmost"),
        ("app_running", "App Is Running"),
        ("window_title_contains", "Window Title Contains"),
        ("profile_active", "Profile Is Active")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "questionmark.diamond")
                    .foregroundColor(.accentColor)
                Text("Configure Conditional Action")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(MGStyle.Spacing.xl)
            .background(MGStyle.Colors.cardBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {

                    // Condition section
                    GroupBox("Condition") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                            // Type picker
                            HStack {
                                Text("Condition:")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 110, alignment: .trailing)
                                Picker("", selection: $conditionType) {
                                    ForEach(conditionOptions, id: \.id) { opt in
                                        Text(opt.label).tag(opt.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                Spacer()
                            }
                            // Negate toggle
                            Toggle("Negate (execute when condition is NOT met)", isOn: $conditionNegate)
                            // App picker (visible for app_frontmost / app_running)
                            if conditionType == "app_frontmost" || conditionType == "app_running" {
                                HStack {
                                    Text("Application:")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 110, alignment: .trailing)
                                    Picker("", selection: $conditionApp) {
                                        Text("Select App...").tag("")
                                        ForEach(WindowTargeting.getAllRunningApplications(), id: \.bundleId) { app in
                                            Text(app.name).tag(app.bundleId)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    Spacer()
                                }
                            }
                            // Window title (visible for window_title_contains)
                            if conditionType == "window_title_contains" {
                                HStack {
                                    Text("Title contains:")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 110, alignment: .trailing)
                                    TextField("e.g. Safari", text: $conditionWindowTitle)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            // Profile picker (visible for profile_active)
                            if conditionType == "profile_active" {
                                HStack {
                                    Text("Profile:")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 110, alignment: .trailing)
                                    Picker("", selection: $conditionProfile) {
                                        Text("Select Profile...").tag("")
                                        ForEach(ProfileManager.shared.sortedProfiles, id: \.name) { p in
                                            Text(p.name).tag(p.name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, MGStyle.Spacing.md)
                    }

                    // True branch
                    GroupBox {
                        VStack(alignment: .leading, spacing: 0) {
                            Label("Action when condition is TRUE", systemImage: "checkmark.circle.fill")
                                .font(.system(size: MGStyle.FontSize.body, weight: .semibold))
                                .foregroundColor(.green)
                                .padding(.bottom, MGStyle.Spacing.md)
                            ActionSelectionView(
                                selectedActionId: $trueActionId,
                                actionParameters: $trueActionParams
                            )
                        }
                        .padding(.vertical, MGStyle.Spacing.md)
                    }

                    // False branch
                    GroupBox {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                            Label("Action when condition is FALSE (optional)", systemImage: "xmark.circle")
                                .font(.system(size: MGStyle.FontSize.body, weight: .semibold))
                                .foregroundColor(.secondary)
                            ActionSelectionView(
                                selectedActionId: $falseActionId,
                                actionParameters: $falseActionParams
                            )
                            if !falseActionId.isEmpty {
                                Button("Remove False Branch") {
                                    falseActionId = ""
                                    falseActionParams = [:]
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .font(.system(size: MGStyle.FontSize.caption))
                            }
                        }
                        .padding(.vertical, MGStyle.Spacing.md)
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var condParams: [String: AnyCodable] = [
                        "condition_type": AnyCodable(conditionType),
                        "condition_negate": AnyCodable(conditionNegate)
                    ]
                    if !conditionApp.isEmpty { condParams["condition_app"] = AnyCodable(conditionApp) }
                    if !conditionWindowTitle.isEmpty { condParams["condition_window_title"] = AnyCodable(conditionWindowTitle) }
                    if !conditionProfile.isEmpty { condParams["condition_profile"] = AnyCodable(conditionProfile) }
                    onSave(condParams, trueActionId, trueActionParams, falseActionId, falseActionParams)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trueActionId.isEmpty && conditionType != "always")
            }
            .padding(MGStyle.Spacing.xl)
            .background(MGStyle.Colors.cardBackground)
        }
    }
}
