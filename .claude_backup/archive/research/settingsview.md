# Research: SettingsView UI/UX Polish

## Date: 2026-01-04

## Objective
Polish SettingsView UI/UX to expose all features and improve readability.

## Issues Found

### 1. Hidden Features (violates "no hidden features")
- **MenuBarAppearanceSettings** - tint color, opacity, shadow, border, rounded corners
- All implemented in Core/Services/MenuBarAppearanceService.swift
- NOT exposed in SettingsView.swift

### 2. Collapsed by Default
- AppleScript section uses DisclosureGroup (hidden until clicked)

## SwiftUI APIs to Use

### ColorPicker
- Native SwiftUI component
- Works with `Color` binding
- Supports opacity: `ColorPicker("Color", selection: $color, supportsOpacity: true)`

### Color <-> Hex String Conversion
```swift
extension Color {
    init(hex: String) // Need to implement
    func toHex() -> String // Need to implement
}
```

### Existing Pattern in Codebase
- GroupBoxStyle: GlassGroupBoxStyle already defined
- Toggle pattern: works well
- Slider pattern: used for delays
- HelpButton: used for tips

## Implementation Plan

1. Add "Appearance" GroupBox to Advanced tab:
   - Toggle: Enable custom appearance
   - ColorPicker: Tint color
   - Slider: Tint opacity
   - Toggle: Shadow
   - Toggle: Border
   - Toggle: Rounded corners
   - Slider: Corner radius (when rounded enabled)

2. Remove DisclosureGroup from AppleScript section - make visible by default

## Confidence: High
Using standard SwiftUI components already in codebase.
