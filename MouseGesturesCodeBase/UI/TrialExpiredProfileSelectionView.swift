import SwiftUI

/// A standalone view shown when the trial expires to force the user to pick a single profile for Free mode.
struct TrialExpiredProfileSelectionView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileId: UUID?
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: MGStyle.Spacing.xl) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: MGStyle.Spacing.md) {
                Text("MouseGestures Trial Expired")
                    .font(.title).fontWeight(.bold)
                
                Text("Your MouseGestures trial has expired. Free mode supports only one profile. Please select the profile you want to keep active.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true) // Ensure text wraps
            }
            
            MGContentCard {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                    Text("Select Active Profile")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedProfileId) {
                        Text("Select a profile...").tag(UUID?.none)
                        ForEach(uiServices.profiles) { profile in
                            Text("\(profile.name) (\(profile.gestures.count) actions)")
                                .tag(UUID?.some(profile.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(MGStyle.Spacing.md)
            }
            .frame(maxWidth: 350)
            
            VStack(spacing: MGStyle.Spacing.md) {
                Button(action: {
                    if let profileId = selectedProfileId {
                        uiServices.configuration.freeModeProfileId = profileId
                        uiServices.switchToProfile(profileId)
                        uiServices.configuration.save()
                        onComplete()
                    }
                }) {
                    Text("Confirm Selection")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedProfileId == nil)
                
                Button("Upgrade to Pro") {
                    // This window will close, and we'll tell the app to open the Upgrade tab
                    onComplete()
                    NotificationCenter.default.post(name: .openUpgradeTab, object: nil)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.top, MGStyle.Spacing.md)
        }
        .padding(40)
        .background(MGStyle.Colors.contentBackground)
        .onAppear {
            selectedProfileId = uiServices.activeProfileId
        }
    }
}
