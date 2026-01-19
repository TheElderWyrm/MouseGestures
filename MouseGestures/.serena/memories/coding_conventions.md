# Coding Conventions & Style Guide

## Swift Code Style
- Use Swift 5 features and best practices
- Follow standard Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Use property wrappers appropriately (@Published, @State, etc.)

## Architecture Patterns
- **MVVM Pattern**: ViewModels with @Published properties for SwiftUI bindings
- **Singleton Pattern**: Used for shared services (Configuration.shared, etc.)
- **Plugin Architecture**: Protocol-based plugin system for extensibility

## File Organization
- Group related files in folders (UI/Tabs, ActionPlugins, etc.)
- Keep service classes in Services folder
- Configuration files in Configuration folder

## Naming Conventions
- Views end with "View" (e.g., GesturesView, ProfilesView)
- Services end with "Service" (e.g., ProfileManagementService)
- Plugins end with "Plugin" (e.g., CoreActionsPlugin)

## Error Handling
- Use do-try-catch for operations that can fail
- Log errors using the Logger service
- Return optionals or Bool for non-throwing operations