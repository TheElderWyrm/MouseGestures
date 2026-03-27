import SwiftUI
import AppKit

// MARK: - Conditional Action Editor
//
// A sheet that lets the user pick and configure the "if true" and
// "if false" actions for a Conditional Action.

struct ConditionalActionEditorView: View {

    // Callbacks
    let onSave:   (String, [String: AnyCodable], String, [String: AnyCodable]) -> Void
    let onCancel: () -> Void

    // True branch
    @State private var trueActionId:     String
    @State private var trueActionParams: [String: AnyCodable]

    // False branch
    @State private var falseActionId:     String
    @State private var falseActionParams: [String: AnyCodable]

    @Environment(\.dismiss) private var dismiss

    init(
        trueActionId:     String,
        trueActionParams: [String: AnyCodable],
        falseActionId:    String,
        falseActionParams:[String: AnyCodable],
        onSave:   @escaping (String, [String: AnyCodable], String, [String: AnyCodable]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _trueActionId      = State(initialValue: trueActionId)
        _trueActionParams  = State(initialValue: trueActionParams)
        _falseActionId     = State(initialValue: falseActionId)
        _falseActionParams = State(initialValue: falseActionParams)
        self.onSave   = onSave
        self.onCancel = onCancel
    }

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
                        VStack(alignment: .leading, spacing: 0) {
                            Label("Action when condition is FALSE (optional)", systemImage: "xmark.circle")
                                .font(.system(size: MGStyle.FontSize.body, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, MGStyle.Spacing.md)

                            if falseActionId.isEmpty {
                                Button("Add False Branch…") {
                                    falseActionId = ""
                                    // Just show the picker by setting a non-empty placeholder then clearing
                                    // Actually we just need to show the ActionSelectionView - toggle a flag
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }

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
                                .padding(.top, MGStyle.Spacing.sm)
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
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(trueActionId, trueActionParams, falseActionId, falseActionParams)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trueActionId.isEmpty)
            }
            .padding(MGStyle.Spacing.xl)
            .background(MGStyle.Colors.cardBackground)
        }
    }
}
