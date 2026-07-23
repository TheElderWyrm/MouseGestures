import SwiftUI

struct UpdateNotificationView: View {
    @ObservedObject var updateService = UpdateService.shared
    @ObservedObject var selfUpdateService = SelfUpdateService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showFailureAlert = false
    @State private var failureMessage = ""

    private var canAutoUpdate: Bool {
        selfUpdateService.canSelfUpdateInPlace()
    }

    private var isUpdating: Bool {
        selfUpdateService.isUpdating
    }

    private var updateButtonTitle: String {
        canAutoUpdate ? "Update Now" : "Open Download Page"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Update Available")
                        .font(.system(size: 18, weight: .bold))
                    Text("Version \(updateService.latestVersion) is now available.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }
            .padding(24)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Release Notes
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's New:")
                        .font(.headline)

                    Text(updateService.updateReleaseNotes)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                }
                .padding(24)
            }

            Divider()

            // Footer
            VStack(alignment: .leading, spacing: 12) {
                if !canAutoUpdate {
                    Text("Move MouseGestures to Applications to enable automatic updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                statusView

                HStack {
                    Button("Later") {
                        dismiss()
                    }
                    .buttonStyle(.link)
                    .disabled(isUpdating)

                    Spacer()

                    Button(updateButtonTitle) {
                        handleUpdateNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isUpdating)
                }
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 450)
        .onChange(of: selfUpdateService.stage) { newStage in
            if case .failed(let message) = newStage {
                failureMessage = message
                showFailureAlert = true
            }
        }
        .alert("Update Failed", isPresented: $showFailureAlert) {
            Button("Open Download Page") {
                openDownloadPage()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                selfUpdateService.reset()
            }
        } message: {
            Text(failureMessage)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch selfUpdateService.stage {
        case .idle, .failed:
            EmptyView()
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading update… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ProgressView(value: progress)
            }
        case .mounting:
            statusRow("Preparing installer…")
        case .installing:
            statusRow("Installing update…")
        case .relaunching:
            statusRow("Relaunching MouseGestures…")
        }
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func handleUpdateNow() {
        guard canAutoUpdate else {
            openDownloadPage()
            dismiss()
            return
        }
        selfUpdateService.startSelfUpdate(downloadURLString: updateService.updateDownloadURLString)
    }

    private func openDownloadPage() {
        if let url = URL(string: "https://mousegestures.app/download") {
            NSWorkspace.shared.open(url)
        }
    }
}
