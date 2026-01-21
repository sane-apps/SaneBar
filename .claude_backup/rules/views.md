# SwiftUI View Rules

> Pattern: `**/Views/**/*.swift`, `**/UI/**/*.swift`, `**/*View.swift`

---

## Requirements

1. **Extract if body > 50 lines** - Split into subviews
2. **No business logic in views** - Views render state, don't compute it
3. **Use @Observable** - Not @StateObject (Swift 5.9+)
4. **Computed properties for derived state** - Don't duplicate data

## Right

```swift
struct SettingsView: View {
    @State private var settings: SettingsModel

    var body: some View {
        List {
            GeneralSection(settings: settings)
            PrivacySection(settings: settings)
            AboutSection()
        }
    }
}
```

```swift
// Extracted component - keeps parent clean
struct GeneralSection: View {
    let settings: SettingsModel

    var body: some View {
        Section("General") {
            Toggle("Dark Mode", isOn: $settings.darkMode)
            Picker("Language", selection: $settings.language) { ... }
        }
    }
}
```

## Wrong

```swift
struct SettingsView: View {
    @State private var settings: SettingsModel

    var body: some View {
        List {
            // 200 lines of inline UI with no extraction
            Section("General") { ... }
            Section("Privacy") { ... }
            Section("Advanced") { ... }
            Section("About") { ... }
            // Business logic mixed in
            let filteredItems = items.filter { $0.isActive }
        }
    }
}
```

```swift
// Using deprecated pattern
@StateObject var viewModel = ViewModel()  // Use @State + @Observable instead
```
