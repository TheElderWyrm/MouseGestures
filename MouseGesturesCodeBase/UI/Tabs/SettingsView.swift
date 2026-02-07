import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @StateObject private var registry = SettingsCategoryRegistry.shared
    
    @State private var selectedCategoryId: String = "general"
    @State private var showAdvanced: Bool = false
    @State private var searchText: String = ""
    
    /// Category IDs that match the current search query
    private var matchingCategoryIds: Set<String> {
        registry.matchingCategoryIds(for: searchText)
    }
    
    /// Filtered and sorted providers based on search
    private var filteredProviders: [any SettingsCategoryProvider] {
        let sorted = registry.sortedProviders
        if searchText.isEmpty { return sorted }
        let matching = matchingCategoryIds
        return sorted.filter { matching.contains($0.settingsCategoryId) }
    }
    
    /// Search results for the dropdown
    private var searchResults: [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        registry.searchResults(for: searchText)
    }
    
    var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 260)
            
            contentView
                .frame(minWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Ensure built-in categories are registered
            if registry.providers.isEmpty {
                registerBuiltInSettingsCategories()
            }
            // Default to first category
            if let first = registry.sortedProviders.first {
                selectedCategoryId = first.settingsCategoryId
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search settings…", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            
            // Search results dropdown
            if !searchText.isEmpty && !searchResults.isEmpty {
                searchResultsList
            }
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            
            // Category list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredProviders, id: \.settingsCategoryId) { provider in
                        sidebarItem(for: provider)
                    }
                    
                    if filteredProviders.isEmpty && !searchText.isEmpty {
                        Text("No matching settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 10)
            }
            
            Spacer()
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            
            // Advanced toggle
            HStack {
                Toggle(isOn: $showAdvanced) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text("Advanced")
                            .font(.system(size: 12))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Search Results List
    
    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(searchResults.prefix(8).enumerated()), id: \.offset) { _, result in
                Button(action: {
                    selectedCategoryId = result.categoryId
                    searchText = ""
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(result.categoryTitle)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                if result.item.title != searchResults.prefix(8).last?.item.title {
                    Divider().padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
    
    // MARK: - Sidebar Item
    
    private func sidebarItem(for provider: any SettingsCategoryProvider) -> some View {
        let isSelected = provider.settingsCategoryId == selectedCategoryId
        
        return Button(action: {
            selectedCategoryId = provider.settingsCategoryId
        }) {
            HStack(spacing: 8) {
                Image(systemName: provider.settingsCategoryIcon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .white : .secondary)
                
                Text(provider.settingsCategoryTitle)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Content Area
    
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let provider = registry.sortedProviders.first(where: { $0.settingsCategoryId == selectedCategoryId }) {
                    provider.createSettingsView(showAdvanced: $showAdvanced)
                } else if let first = filteredProviders.first {
                    first.createSettingsView(showAdvanced: $showAdvanced)
                } else {
                    emptyStateView
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No settings found")
                .font(.headline)
                .foregroundColor(.secondary)
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}
