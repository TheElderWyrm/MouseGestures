import SwiftUI

struct OnboardingView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var currentPage = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to MouseGestures",
            description: "MouseGestures allows you to trigger system-wide actions by moving your mouse into screen corners or edges while holding modifiers.",
            image: "hand.draw.fill",
            color: .blue
        ),
        OnboardingPage(
            id: "zones",
            title: "Screen Zones",
            description: "The screen is divided into 8 zones: 4 corners and 4 edges. Configure gestures to trigger when you enter these zones.",
            image: "rectangle.inset.filled",
            color: .purple
        ),
        OnboardingPage(
            title: "Modifier Keys",
            description: "Combine mouse movements with Cmd, Opt, Ctrl, or Shift to unlock hundreds of unique gestures without accidentally triggering them.",
            image: "command",
            color: .orange
        ),
        OnboardingPage(
            title: "App Profiles",
            description: "Create custom profiles for different apps. Your gestures will automatically switch when you change your focused application.",
            image: "app.badge",
            color: .green
        ),
        OnboardingPage(
            title: "Permissions",
            description: "MouseGestures requires Accessibility permissions to monitor mouse movement and trigger actions. We never collect or transmit your data.",
            image: "lock.shield",
            color: .red
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content
            ZStack {
                ForEach(0..<pages.count, id: \.self) { index in
                    if index == currentPage {
                        OnboardingPageView(page: pages[index])
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack {
                // Page Indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onComplete()
                    }
                    .buttonStyle(.link)
                    
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.leading, 10)
                } else {
                    HStack(spacing: 12) {
                        Button("Maybe Later") {
                            onComplete()
                        }
                        .buttonStyle(.link)
                        
                        Button("Create My First Action") {
                            onComplete()
                            uiServices.tutorialService.startTutorial()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 400)
    }
}

struct OnboardingPage {
    var id: String? = nil
    let title: String
    let description: String
    let image: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: page.image)
                    .font(.system(size: 60))
                    .foregroundColor(page.color)
            }
            .padding(.top, 20)
            
            Text(page.title)
                .font(.system(size: 24, weight: .bold))
            
            Text(page.description)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
//            if page.id == "zones" {
//                ZoneQuickSettingsView()
//                    .padding(.top, 10)
//            }
            
            Spacer()
        }
        .padding()
    }
}

struct ZoneQuickSettingsView: View {
    @State private var showHighlights = ZoneVisualizationService.shared.isShowZoneHighlights()
    @State private var showLabels = ZoneVisualizationService.shared.isShowZoneLabels()
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Quick Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Zone Highlights", isOn: $showHighlights)
                    .onChange(of: showHighlights) { newValue in
                        ZoneVisualizationService.shared.setShowZoneHighlights(newValue)
                    }
                    
                Toggle("Show Zone Labels", isOn: $showLabels)
                    .onChange(of: showLabels) { newValue in
                        ZoneVisualizationService.shared.setShowZoneLabels(newValue)
                    }
                    .disabled(!showHighlights)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
                
            Button(action: {
                ZoneHighlightManager.shared.showPreview(duration: 5.0)
            }) {
                Label("Preview Zones", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
        .padding(.horizontal, 40)
    }
}
