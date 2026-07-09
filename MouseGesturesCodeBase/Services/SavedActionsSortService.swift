import Foundation

// MARK: - Saved Actions Sort Service
// Single-purpose service for sorting and organizing saved actions

class SavedActionsSortService {
    static let shared = SavedActionsSortService()

    private init() {}

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateModified = "Date Modified"
        case category = "Category"
    }

    // MARK: - Sorting

    func sortActions(_ actions: [SavedAction], by order: SortOrder) -> [SavedAction] {
        return actions.sorted { lhs, rhs in
            switch order {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateCreated:
                return lhs.dateCreated > rhs.dateCreated
            case .dateModified:
                return lhs.dateModified > rhs.dateModified
            case .category:
                let categoryComparison = lhs.typeDisplayName.localizedCaseInsensitiveCompare(rhs.typeDisplayName)
                if categoryComparison == .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return categoryComparison == .orderedAscending
            }
        }
    }

    // MARK: - Filtering

    func filterActions(_ actions: [SavedAction], searchText: String) -> [SavedAction] {
        guard !searchText.isEmpty else { return actions }

        let lowercasedQuery = searchText.lowercased()

        return actions.filter { action in
            action.name.lowercased().contains(lowercasedQuery) ||
            action.typeDisplayName.lowercased().contains(lowercasedQuery) ||
            action.description.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Grouping

    func groupActionsByCategory(_ actions: [SavedAction]) -> [String: [SavedAction]] {
        var grouped: [String: [SavedAction]] = [:]

        for action in actions {
            let category = action.typeDisplayName
            if grouped[category] == nil {
                grouped[category] = []
            }
            grouped[category]?.append(action)
        }

        return grouped
    }

    // MARK: - Action Icon Determination

    func getIconForAction(_ action: SavedAction) -> String {
        let identifier = action.actionIdentifier.lowercased()

        if identifier.contains("window") {
            return "rectangle.3.group"
        } else if identifier.contains("media") || identifier.contains("play") || identifier.contains("volume") {
            return "play.circle"
        } else if identifier.contains("system") || identifier.contains("mission") || identifier.contains("expose") {
            return "squares.below.rectangle"
        } else if identifier.contains("automation") || identifier.contains("script") {
            return "gearshape.2"
        } else {
            return "star"
        }
    }
}
