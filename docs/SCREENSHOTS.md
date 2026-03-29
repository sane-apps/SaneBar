# SaneBar Screenshot Catalog (Current)

> Last Updated: 2026-02-25
> Purpose: website + onboarding + README asset reference

## Primary Marketing Screenshots (Website)

| File | Purpose | Where Used |
|---|---|---|
| `docs/images/icon-panel.png` | Browse mode: Icon Panel | `docs/index.html` hero carousel |
| `docs/images/second-menu-bar.png` | Browse mode: Second Menu Bar | `docs/index.html` hero carousel |
| `docs/images/browse-settings.png` | General > Browse Icons section | `docs/index.html` hero carousel |
| `docs/images/find-icon.png` | Find Icon / Browse grid | Website feature card + README |
| `docs/images/settings-rules.png` | Rules + triggers | Website feature cards + README |
| `docs/images/settings-appearance.png` | Appearance controls | Website feature cards + README |
| `docs/images/settings-shortcuts.png` | Shortcuts + automation | Website feature cards + README |
| `docs/images/touchid-prompt.png` | Touch ID lock proof | Website feature card |
| `docs/images/spacing.png` | Menu bar spacing controls | Website feature card |
| `docs/images/branding.png` | Brand hero/logo | Website + social |

## Settings Reference Screenshots

| File | Tab | Notes |
|---|---|---|
| `docs/images/settings-general.png` | General | Must show Browse Icons controls |
| `docs/images/settings-rules.png` | Rules | Must show triggers/rehide controls |
| `docs/images/settings-appearance.png` | Appearance | Must show icon + style + layout controls |
| `docs/images/settings-shortcuts.png` | Shortcuts | Must show hotkeys + automation |
| `docs/images/settings-about.png` | About | About tab |

## Onboarding Assets (App Bundle)

| Asset | Path | Source |
|---|---|---|
| `OnboardingIconPanel` | `Resources/Assets.xcassets/OnboardingIconPanel.imageset/icon-panel.png` | Match `docs/images/icon-panel.png` |
| `OnboardingSecondMenuBar` | `Resources/Assets.xcassets/OnboardingSecondMenuBar.imageset/second-menu-bar.png` | Match `docs/images/second-menu-bar.png` |
| `OnboardingBrowseSettings` | `Resources/Assets.xcassets/OnboardingBrowseSettings.imageset/browse-settings.png` | Match `docs/images/browse-settings.png` |

## Capture Process

1. Launch app build you want to document.
2. Open target windows/states.
3. Capture via `scripts/marketing_screenshots.rb`.
4. Copy/rename final images into `docs/images/`.
5. Mirror 3 browse images to onboarding image sets.
6. Validate all references in `docs/index.html` and onboarding compile.

## Drift Guard

When Browse Icons UI changes, update all 4 in one pass:
- `docs/images/icon-panel.png`
- `docs/images/second-menu-bar.png`
- `docs/images/browse-settings.png`
- onboarding equivalents in `Resources/Assets.xcassets/*`

Also review:
- `docs/index.html`
- `README.md`
- `UI/Onboarding/WelcomeView.swift`
