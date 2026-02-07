import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @StateObject private var registry = SettingsCategoryRegistry.shared
    
    @State private var selectedCategoryId: String = "general"
    @State private var showAdvanced: Bool = false
    @State private var searchText: String = ""
    @State private var selectedSubcategoryIds: [String: String] = [:]  // categoryId -> subcategoryId
    
    private var filteredCategories: [ResolvedCategory] {
        let cats = registry.categories
        if searchText.isEmpty { return cats }
        let matching = registry.matchingCategoryIds(for: searchText)
        return cats.filter { matching.contains($0.id) }
    }
    
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
            if registry.entries.isEmpty {
                registerAllSettings()
            }
            if let first = registry.categories.first {
                selectedCategoryId = first.id
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            
            if !searchText.isEmpty && !searchResults.isEmpty {
                searchResultsList
            }
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredCategories, id: \.id) { cat in
                        sidebarItem(for: cat)
                    }
                    
                    if filteredCategories.isEmpty && !searchText.isEmpty {
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
    
    // MARK: - Search Results
    
    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
        ForEach(searchResults.prefix(8), id: \.item.id) { result in
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
    
    private func sidebarItem(for cat: ResolvedCategory) -> some View {
        let isSelected = cat.id == selectedCategoryId
        
        return Button(action: { selectedCategoryId = cat.id }) {
            HStack(spacing: 8) {
                Image(systemName: cat.icon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .white : .secondary)
                Text(cat.title)
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
                if let cat = registry.category(id: selectedCategoryId) {
                    categoryContentView(for: cat)
                } else if let first = filteredCategories.first {
                    categoryContentView(for: first)
                } else {
                    emptyStateView
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    /// Renders a full category: header, top-level entries card, subcategory picker + entries card
    @ViewBuilder
    private func categoryContentView(for cat: ResolvedCategory) -> some View {
        // Category header
        Text(cat.title)
            .font(.title2)
            .fontWeight(.semibold)
        
        // Top-level entries (no subcategory)
        let visibleTopLevel = cat.topLevelEntries.filter { !$0.isAdvanced || showAdvanced }
        if !visibleTopLevel.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                ForEach(visibleTopLevel.indices, id: \.self) { idx in
                    visibleTopLevel[idx].viewBuilder($showAdvanced)
                    if idx < visibleTopLevel.count - 1 { Divider() }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
        
        // Subcategories
        if cat.hasSubcategories {
            subcategoryView(for: cat)
        }
    }
    
    /// Renders the subcategory picker and entries for the selected subcategory
    @ViewBuilder
    private func subcategoryView(for cat: ResolvedCategory) -> some View {
        let visibleSubs = cat.subcategories.filter { sub in
            sub.entries.contains { !$0.isAdvanced || showAdvanced }
        }
        
        if visibleSubs.count > 1 {
            Picker("", selection: subcategorySelection(for: cat, visibleSubs: visibleSubs)) {
                ForEach(visibleSubs, id: \.id) { sub in
                    Label(sub.title, systemImage: sub.icon).tag(sub.id)
                }
            }
            .pickerStyle(.segmented)
        }
        
        // Entries for the selected subcategory
        let selectedSubId = selectedSubcategoryIds[cat.id] ?? visibleSubs.first?.id ?? ""
        if let sub = visibleSubs.first(where: { $0.id == selectedSubId }) ?? visibleSubs.first {
            let visibleEntries = sub.entries.filter { !$0.isAdvanced || showAdvanced }
            
            if !visibleEntries.isEmpty {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(visibleEntries.indices, id: \.self) { idx in
                        visibleEntries[idx].viewBuilder($showAdvanced)
                        if idx < visibleEntries.count - 1 { Divider() }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }
    
    /// Binding for subcategory selection within a category
    private func subcategorySelection(for cat: ResolvedCategory, visibleSubs: [ResolvedSubcategory]) -> Binding<String> {
        Binding(
            get: {
                let current = selectedSubcategoryIds[cat.id]
                // If current selection isn't in visible subs, default to first
                if let current = current, visibleSubs.contains(where: { $0.id == current }) {
                    return current
                }
                return visibleSubs.first?.id ?? ""
            },
            set: { newValue in
                selectedSubcategoryIds[cat.id] = newValue
            }
        )
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
