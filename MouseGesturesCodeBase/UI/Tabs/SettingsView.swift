import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @StateObject private var registry = SettingsCategoryRegistry.shared
    @ObservedObject private var license = LicenseService.shared
    @ObservedObject private var pluginExtensions = PluginExtensionManager.shared

    @State private var selectedCategoryId: String = "general"
    @State private var showAdvanced: Bool = false
    @State private var searchText: String = ""
    @State private var selectedSubcategoryIds: [String: String] = [:]

    private var isDeveloperModeEnabled: Bool {
        UIServices.shared.isDeveloperModeEnabled()
    }

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
                .frame(minWidth: MGStyle.Layout.sidebarMinWidth, idealWidth: 230, maxWidth: 260)

            contentView
                .frame(minWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: pluginExtensions.registrationCount) { _ in
            registerAllSettings()   // a plugin was installed, removed or reloaded: refresh the plugin tabs
        }
        .onAppear {
            registerAllSettings()   // plugin tabs depend on what is loaded right now

            if let first = registry.categories.first {
                selectedCategoryId = first.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        MGSidebar(title: "Settings") {
            ForEach(filteredCategories, id: \.id) { cat in
                MGSidebarItem(
                    title: cat.title,
                    icon: cat.isPro && !license.isPro ? "lock.fill" : cat.icon,
                    badge: cat.isPro ? "PRO" : nil,
                    isSelected: cat.id == selectedCategoryId,
                    action: { selectedCategoryId = cat.id }
                )
            }

            if filteredCategories.isEmpty && !searchText.isEmpty {
                Text("No matching settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, MGStyle.Spacing.lg)
                    .padding(.vertical, MGStyle.Spacing.lg)
            }
        } header: {
            VStack(spacing: 0) {
                MGSearchField("Search settings…", text: $searchText)
                    .padding(.horizontal, MGStyle.Spacing.xl)
                    .padding(.bottom, MGStyle.Spacing.lg)

                if !searchText.isEmpty && !searchResults.isEmpty {
                    searchResultsList
                }
            }
        } footer: {
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, MGStyle.Spacing.xxl)
                    .padding(.vertical, MGStyle.Spacing.md)

                HStack {
                    if LicenseService.shared.isPro {
                        Toggle(isOn: $showAdvanced) {
                            HStack(spacing: MGStyle.Spacing.md) {
                                Image(systemName: "slider.horizontal.3")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                Text("Advanced")
                                    .font(.system(size: MGStyle.FontSize.caption))
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    } else {
                        EmptyView()
                            .onAppear { showAdvanced = false }
                    }

                    Spacer()
                }
                .padding(.horizontal, MGStyle.Spacing.xxl)
                .padding(.bottom, MGStyle.Spacing.xl)
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchResults.prefix(8), id: \.item.id) { result in
                Button(action: {
                    selectedCategoryId = result.categoryId
                    searchText = ""
                }) {
                    HStack(spacing: MGStyle.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: MGStyle.FontSize.badge))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.item.title)
                                .font(.system(size: MGStyle.IconSize.inline, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(result.categoryTitle)
                                .font(.system(size: MGStyle.FontSize.badge))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, MGStyle.Spacing.lg)
                    .padding(.vertical, MGStyle.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                if result.item.title != searchResults.prefix(8).last?.item.title {
                    Divider().padding(.horizontal, MGStyle.Spacing.lg)
                }
            }
        }
        .padding(.vertical, MGStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .fill(MGStyle.Colors.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .stroke(MGStyle.Colors.separator, lineWidth: 0.5)
        )
        .padding(.horizontal, MGStyle.Spacing.xl)
        .padding(.bottom, MGStyle.Spacing.md)
    }

    // MARK: - Content Area

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                if let cat = registry.category(id: selectedCategoryId) {
                    categoryContentView(for: cat)
                } else if let first = filteredCategories.first {
                    categoryContentView(for: first)
                } else {
                    MGEmptyState(
                        icon: "magnifyingglass",
                        title: "No settings found",
                        description: !searchText.isEmpty ? "Try a different search term" : nil
                    )
                }
            }
            .padding(MGStyle.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func categoryContentView(for cat: ResolvedCategory) -> some View {
        MGSectionHeader(cat.title)

        let visibleTopLevel = cat.topLevelEntries.filter { !$0.isAdvanced || showAdvanced }
        if !visibleTopLevel.isEmpty {
            MGContentCard {
                ForEach(visibleTopLevel.indices, id: \.self) { idx in
                    visibleTopLevel[idx].viewBuilder($showAdvanced)
                    if idx < visibleTopLevel.count - 1 { Divider() }
                }
            }
        }

        if cat.hasSubcategories {
            subcategoryView(for: cat)
        }
    }

    @ViewBuilder
    private func subcategoryView(for cat: ResolvedCategory) -> some View {
        let visibleSubs = cat.subcategories.filter { sub in
            sub.entries.contains { !$0.isAdvanced || showAdvanced }
        }

        if visibleSubs.count > 1 {
            SubcategoryTabBar(tabs: visibleSubs.map { ($0.id, $0.title, $0.icon) },
                              selection: subcategorySelection(for: cat, visibleSubs: visibleSubs))
        }

        let selectedSubId = selectedSubcategoryIds[cat.id] ?? visibleSubs.first?.id ?? ""
        if let sub = visibleSubs.first(where: { $0.id == selectedSubId }) ?? visibleSubs.first {
            let visibleEntries = sub.entries.filter { !$0.isAdvanced || showAdvanced }

            if !visibleEntries.isEmpty {
                MGContentCard {
                    ForEach(visibleEntries.indices, id: \.self) { idx in
                        visibleEntries[idx].viewBuilder($showAdvanced)
                        if idx < visibleEntries.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func subcategorySelection(for cat: ResolvedCategory, visibleSubs: [ResolvedSubcategory]) -> Binding<String> {
        Binding(
            get: {
                let current = selectedSubcategoryIds[cat.id]
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
}


// MARK: - Subcategory Tab Bar

/// Content-sized tabs. When every icon + title no longer fits, only the selected tab keeps its title; if even that
/// is too wide, all tabs collapse to their symbol (the title stays available as a tooltip).
struct SubcategoryTabBar: View {
    let tabs: [(id: String, title: String, icon: String)]
    @Binding var selection: String

    private enum Style { case full, selectedOnly, iconOnly }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(.full)
            bar(.selectedOnly)
            bar(.iconOnly)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(_ style: Style) -> some View {
        HStack(spacing: MGStyle.Spacing.sm) {
            ForEach(tabs, id: \.id) { tab in
                let selected = tab.id == selection
                let showTitle = style == .full || (style == .selectedOnly && selected)
                Button { selection = tab.id } label: {
                    HStack(spacing: MGStyle.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(.system(size: MGStyle.IconSize.row))
                        if showTitle {
                            Text(tab.title)
                                .font(.system(size: MGStyle.FontSize.body, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, MGStyle.Spacing.lg)
                    .padding(.vertical, MGStyle.Spacing.md - 1)
                    .foregroundColor(selected ? .accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                            .fill(selected ? MGStyle.Colors.selectedRow : MGStyle.Colors.subtleOverlay)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
