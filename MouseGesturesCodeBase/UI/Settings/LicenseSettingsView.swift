import SwiftUI

struct LicenseSettingsView: View {
    @ObservedObject var licenseService = LicenseService.shared
    @State private var licenseKeyInput = ""
    @State private var showingActivatedAlert = false
    @State private var activationError: String?
    @State private var isActivating = false

    private let purchaseURL = URL(string: "https://mousegestures.app/purchase")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                statusCard

                if licenseService.status == .pro {
                    activeLicenseSection
                } else {
                    activationSection
                    proFeaturesList
                }
            }
            .padding(MGStyle.Spacing.xl)
        }
        .alert("Pro Activated", isPresented: $showingActivatedAlert) {
            Button("Awesome", role: .cancel) { }
        } message: {
            Text("Your license key was verified. You now have access to all Pro features. Enjoy!")
        }
        .alert("Activation Error", isPresented: Binding(
            get: { activationError != nil },
            set: { _ in activationError = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = activationError {
                Text(error)
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: MGStyle.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                if licenseService.status == .pro {
                    Text("Pro Activated")
                        .font(.system(size: MGStyle.FontSize.heading, weight: .bold))
                    Text("Thank you for supporting MouseGestures!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(licenseService.status == .expired ? "Free" : licenseService.status.rawValue)
                        .font(.system(size: MGStyle.FontSize.heading, weight: .bold))

                    if licenseService.isTrial {
                        Text("\(licenseService.trialDaysRemaining) days remaining in your trial")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Basic features only")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(MGStyle.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
        .overlay(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator, lineWidth: 0.5))
    }

    // MARK: - Activation (not Pro)

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            Text(licenseService.isTrial ? "Activate Pro License" : "Upgrade to Pro")
                .font(.headline)

            Text("Enter the license key from your purchase confirmation to unlock all "
                + "Pro features. A purchased key verifies once online, then MouseGestures "
                + "works fully offline — no account, ever.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: MGStyle.Spacing.md) {
                TextField("Paste your license key", text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isActivating)
                    .onSubmit(activate)

                Button(action: activate) {
                    if isActivating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
            }

            if let url = purchaseURL {
                Button("Purchase a License...") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(MGStyle.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.subtleOverlay))
    }

    // MARK: - Active License (Pro)

    private var activeLicenseSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("License")
                .font(.headline)

            if let key = licenseService.storedLicenseKeyDisplay {
                HStack {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                }
            }

            Button("Deactivate on this Mac") {
                licenseService.deactivateLicense()
                licenseKeyInput = ""
            }
            .buttonStyle(.link)
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding(MGStyle.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.subtleOverlay))
    }

    private func activate() {
        let trimmed = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isActivating else { return }
        isActivating = true
        licenseService.activateLicense(trimmed) { result in
            isActivating = false
            switch result {
            case .success:
                licenseKeyInput = ""
                showingActivatedAlert = true
            case .invalidKey:
                activationError = "That license key isn't valid. Double-check it against your purchase confirmation and try again."
            case .activationLimitReached:
                activationError = "This license is already active on its maximum number of Macs. "
                    + "Deactivate it on another Mac first, or email support@mousegestures.app."
            case .networkError:
                activationError = "Couldn't reach the license server. Check your internet connection and try again."
            }
        }
    }

    private var proFeaturesList: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("Pro Features")
                .font(.system(size: MGStyle.FontSize.body, weight: .semibold))

            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                featureRow(icon: "rectangle.stack", title: "Unlimited Profiles", description: "Create specific gesture sets for different workflows.")
                featureRow(icon: "app.badge", title: "App-Specific Targeting", description: "Automatically switch profiles when switching apps.")
                featureRow(icon: "slider.horizontal.3", title: "Advanced Settings", description: "Fine-tune app behavior and performance parameters.")
                featureRow(icon: "bolt.fill", title: "Advanced Actions", description: "Access automation, scripting, and bundled actions.")
                featureRow(icon: "gearshape.2", title: "Services & Plugins", description: "Extend functionality with custom service plugins.")
            }
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: MGStyle.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch licenseService.status {
        case .pro: return .green
        case .trial: return .blue
        case .free: return .orange
        case .expired: return .red
        }
    }

    private var statusIcon: String {
        switch licenseService.status {
        case .pro: return "checkmark.seal.fill"
        case .trial: return "clock.fill"
        case .free: return "person.fill"
        case .expired: return "exclamationmark.triangle.fill"
        }
    }
}
