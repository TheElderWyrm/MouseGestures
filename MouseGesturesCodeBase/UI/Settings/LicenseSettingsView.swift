import SwiftUI
import StoreKit

struct LicenseSettingsView: View {
    @ObservedObject var licenseService = LicenseService.shared
    @StateObject var paymentService = PaymentService.shared
    @State private var showingPurchaseAlert = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
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
                        Text(licenseService.status.rawValue)
                            .font(.system(size: MGStyle.FontSize.heading, weight: .bold))
                        
                        if licenseService.isTrial && !PaymentService.shared.isProUnlocked {
                            Text("\(licenseService.trialDaysRemaining) days remaining in your trial")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if licenseService.isPro {
                            Text("Thank you for supporting MouseGestures!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Basic features only")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(MGStyle.Spacing.lg)
                .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
                .overlay(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator, lineWidth: 0.5))
                
                if licenseService.status != .pro {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                        Text(licenseService.isTrial ? "Purchase Pro License" : "Upgrade to Pro")
                            .font(.headline)
                        
                        if paymentService.products.isEmpty {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Loading products...")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        } else {
                            VStack(spacing: MGStyle.Spacing.md) {
                                ForEach(paymentService.products, id: \.id) { product in
                                    purchaseRow(for: product)
                                }
                            }
                        }
                        
                        Button("Restore Previous Purchases") {
                            Task {
                                await paymentService.restorePurchases()
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(MGStyle.Spacing.lg)
                    .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.subtleOverlay))
                    
                    proFeaturesList
                }
                
                if UIServices.shared.isDeveloperModeEnabled() {
                    Divider()
                    HStack(spacing: MGStyle.Spacing.xl) {
                        HStack(spacing: MGStyle.Spacing.md) {
                            Text("Developer Actions:").font(.caption).foregroundColor(.secondary)
                            Button("Reset Trial") { licenseService.resetTrial() }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                        
                        Toggle("Force Free Mode (Test)", isOn: $licenseService.forceFreeMode)
                            .font(.caption)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(MGStyle.Spacing.xl)
        }
        .alert("Pro Activated", isPresented: $showingPurchaseAlert) {
            Button("Awesome", role: .cancel) { }
        } message: {
            Text("You now have access to all Pro features. Enjoy!")
        }
        .alert("Purchase Error", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = purchaseError {
                Text(error)
            }
        }
    }
    
    private func purchaseRow(for product: Product) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.subheadline).fontWeight(.medium)
                Text(product.description)
                    .font(.caption).foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    isPurchasing = true
                    do {
                        if try await paymentService.purchase(product) {
                            showingPurchaseAlert = true
                        }
                    } catch {
                        purchaseError = error.localizedDescription
                    }
                    isPurchasing = false
                }
            }) {
                Text(product.displayPrice)
                    .fontWeight(.bold)
                    .frame(width: 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPurchasing)
        }
        .padding(MGStyle.Spacing.md)
        .background(RoundedRectangle(cornerRadius: MGStyle.Corner.sm).fill(Color.primary.opacity(0.05)))
    }
    
    private var proFeaturesList: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("Pro Features")
                .font(.system(size: MGStyle.FontSize.body, weight: .semibold))
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                featureRow(icon: "rectangle.stack", title: "Unlimited Profiles", description: "Create specific gesture sets for different workflows.")
                featureRow(icon: "app.badge", title: "App-Specific Targeting", description: "Automatically switch profiles when switching apps.")
                featureRow(icon: "bolt.fill", title: "Advanced Actions", description: "Access automation, scripting, and bundled actions.")
                featureRow(icon: "gearshape.2", title: "Services & Plugins", description: "Extend functionality with custom service plugins.")
                featureRow(icon: "flowchart", title: "Efficiency Gating", description: "Fine-tune detection for maximum performance.")
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
