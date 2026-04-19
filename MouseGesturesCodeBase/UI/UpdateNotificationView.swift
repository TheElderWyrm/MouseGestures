import SwiftUI

struct UpdateNotificationView: View {
    @ObservedObject var updateService = UpdateService.shared
    @Environment(\.dismiss) private var dismiss
    
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
            HStack {
                Button("Later") {
                    dismiss()
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Update Now") {
                    // In a real app, this would trigger Sparkle or download the DMG
                    if let url = URL(string: "https://mousegestures.app/download") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 450)
    }
}
