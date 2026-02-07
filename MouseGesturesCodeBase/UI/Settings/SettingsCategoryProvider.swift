import SwiftUI

// MARK: - Settings Category Provider Protocol

/// Protocol for anything that provides a complete settings category/section in the Settings tab.
/// Plugins, services, and built-in components can conform to register their settings dynamically.
protocol SettingsCategoryProvider {
    /// Unique identifier for this settings category
    var settingsCategoryId: String { get }
    /// Display title shown in the sidebar
    var settingsCategoryTitle: String { get }
    /// SF Symbol name for the sidebar icon
    var settingsCategoryIcon: String { get }
    /// Sort order — lower values appear higher in the sidebar
    var settingsCategoryOrder: Int { get }
    /// Searchable items within this category (used by settings search)
    var settingsSearchableItems: [SearchableSettingItem] { get }
    
    /// Create the SwiftUI view for this settings category
    @MainActor
    func createSettingsView(showAdvanced: Binding<Bool>) -> AnyView
}

// MARK: - Settings Item Contributor Protocol

/// Protocol for services/plugins that contribute individual setting items to an existing category.
/// For example, HapticFeedbackService contributes a toggle to the "general" category
/// without needing to own the entire category.
protocol SettingsItemContributor {
    /// The settings contributions this service/plugin provides
    var settingsContributions: [SettingsContribution] { get }
}

/// A single settings contribution: a view + metadata placed into a target category.
struct SettingsContribution {
    /// The category ID to contribute to (e.g. "general")
    let targetCategoryId: String
    /// Sort order within the category (lower = higher position)
    let order: Int
    /// Searchable items for this contribution
    let searchableItems: [SearchableSettingItem]
    /// Builds the settings view for this contribution
    let viewBuilder: @MainActor () -> AnyView
}

// MARK: - Searchable Setting Item

/// Represents a single searchable setting for the settings search functionality.
struct SearchableSettingItem {
    let title: String
    let description: String
    let keywords: [String]
    
    func matches(query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q) ||
               description.lowercased().contains(q) ||
               keywords.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Settings Category Registry

/// Central registry that collects all settings categories and individual contributions.
/// The Settings tab reads from this registry to dynamically build its sidebar and content.
class SettingsCategoryRegistry: ObservableObject {
    static let shared = SettingsCategoryRegistry()
    
    @Published private(set) var providers: [any SettingsCategoryProvider] = []
    @Published private(set) var contributions: [SettingsContribution] = []
    
    private init() {}
    
    /// All providers sorted by their declared order
    var sortedProviders: [any SettingsCategoryProvider] {
        providers.sorted { $0.settingsCategoryOrder < $1.settingsCategoryOrder }
    }
    
    // MARK: - Category Registration
    
    /// Register a settings category provider. Replaces any existing provider with the same ID.
    func register(_ provider: any SettingsCategoryProvider) {
        providers.removeAll { $0.settingsCategoryId == provider.settingsCategoryId }
        providers.append(provider)
    }
    
    /// Unregister a provider by category ID
    func unregister(id: String) {
        providers.removeAll { $0.settingsCategoryId == id }
    }
    
    // MARK: - Item Contribution Registration
    
    /// Register all contributions from a contributor.
    func registerContributions(from contributor: any SettingsItemContributor) {
        for contribution in contributor.settingsContributions {
            contributions.append(contribution)
        }
    }
    
    /// Clear all contributions (useful before re-discovery)
    func clearContributions() {
        contributions.removeAll()
    }
    
    /// Get sorted contributions for a specific category
    func contributions(for categoryId: String) -> [SettingsContribution] {
        contributions
            .filter { $0.targetCategoryId == categoryId }
            .sorted { $0.order < $1.order }
    }
    
    // MARK: - Search
    
    /// All searchable items across all providers and contributions
    private var allSearchableItems: [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        var items: [(String, String, SearchableSettingItem)] = []
        
        // From category providers
        for p in providers {
            for item in p.settingsSearchableItems {
                items.append((p.settingsCategoryId, p.settingsCategoryTitle, item))
            }
        }
        
        // From contributions
        for c in contributions {
            if let p = providers.first(where: { $0.settingsCategoryId == c.targetCategoryId }) {
                for item in c.searchableItems {
                    items.append((c.targetCategoryId, p.settingsCategoryTitle, item))
                }
            }
        }
        
        return items
    }
    
    /// Returns the set of category IDs that match the given search query.
    func matchingCategoryIds(for query: String) -> Set<String> {
        guard !query.isEmpty else {
            return Set(providers.map(\.settingsCategoryId))
        }
        let q = query.lowercased()
        var result = Set<String>()
        for (catId, catTitle, item) in allSearchableItems {
            if catTitle.lowercased().contains(q) || item.matches(query: q) {
                result.insert(catId)
            }
        }
        return result
    }
    
    /// Returns all matching items across all categories for a given query.
    func searchResults(for query: String) -> [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        guard !query.isEmpty else { return [] }
        return allSearchableItems.filter { $0.item.matches(query: query) }
    }
}
