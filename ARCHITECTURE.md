# SaneBar Architecture

Last updated: 2026-02-09

This document explains how SaneBar is structured, how it moves menu bar icons, and how the major services interact. It is written to be useful to any developer (Swift, macOS, or otherwise).

## Goals and Non-Goals

Goals
- Provide reliable hide/show of menu bar icons.
- Programmatically move icons between zones (visible/hidden/always-hidden) via CGEvent Cmd+drag.
- Keep all data on-device; avoid telemetry and external dependencies for core behavior.
- Make behavior predictable (clear triggers, clear state).
- Keep the app safe to run at login and in headless/test contexts.

Non-goals
- No cloud services for core features.
- No direct manipulation of other app windows.

## System Context

SaneBar is a macOS menu bar app that relies on:
- NSStatusItem for the menu bar UI.
- Accessibility (AXUIElement) to read and interact with menu bar items.
- Sparkle for updates (appcast feed).
- CoreWLAN and Focus Mode files for automation triggers.

The app itself is a single process with modular services that all route through MenuBarManager.

## Architecture Principles

- Single orchestration point: MenuBarManager is the source of truth for state.
- Services are small and focused (one responsibility per service).
- User intent wins: manual reveal pins visibility until explicit hide.
- Safe defaults: start expanded, validate, then hide.
- Main-thread safety: UI state changes are @MainActor.

## Core Components (What does what)

| Component | Responsibility | Key Files |
|---|---|---|
| MenuBarManager | Orchestrates state, services, and user actions | `Core/MenuBarManager.swift` |
| StatusBarController | Creates and configures status items and menu | `Core/Controllers/StatusBarController.swift` |
| HidingService | Controls hide/show via delimiter length toggle | `Core/Services/HidingService.swift` |
| AccessibilityService | Reads menu bar items and performs AX actions | `Core/Services/AccessibilityService.swift` (+ extensions) |
| SearchService | Finds hidden icons and activates them | `Core/Services/SearchService.swift` |
| SettingsController | Loads/saves settings, publishes changes | `Core/Controllers/SettingsController.swift` |
| PersistenceService | JSON storage for settings and profiles | `Core/Services/PersistenceService.swift` |
| TriggerService | App launch + low battery triggers | `Core/Services/TriggerService.swift` |
| NetworkTriggerService | WiFi SSID triggers | `Core/Services/NetworkTriggerService.swift` |
| FocusModeService | Focus Mode triggers | `Core/Services/FocusModeService.swift` |
| HoverService | Hover/scroll/click reveal triggers | `Core/Services/HoverService.swift` |
| MenuBarAppearanceService | Menu bar visual styling | `Core/Services/MenuBarAppearanceService.swift` |
| MenuBarSpacingService | System-wide spacing adjustments | `Core/Services/MenuBarSpacingService.swift` |
| UpdateService | Sparkle updates | `Core/Services/UpdateService.swift` |
| AppleScriptCommands | Automation via AppleScript | `Core/Services/AppleScriptCommands.swift` |
| SearchWindowController | Floating Find Icon window | `UI/SearchWindow/SearchWindowController.swift` |
| Onboarding | First-run flow | `UI/Onboarding/*` |

## Key Flows

### App Launch
1. `main.swift` starts app and AppDelegate.
2. AppDelegate sets activation policy, initializes MenuBarManager.
3. MenuBarManager loads settings, then runs deferred UI setup.
4. Status items created, services configured, triggers started if enabled.
5. Initial hide happens after a short delay (unless external monitor rule blocks it).

### Show/Hide Toggle (User Click or Hotkey)
1. User action calls MenuBarManager.toggleHiddenItems().
2. If auth is required and items are hidden, LocalAuthentication is prompted.
3. HidingService toggles delimiter length.
4. MenuBarManager schedules auto-rehide if enabled.
5. Accessibility cache invalidated so Find Icon is accurate.

### Find Icon (Search Window)
1. User opens Search window (Option-click or hotkey).
2. SearchWindowController suspends hover triggers.
3. SearchService queries AccessibilityService cache (or refreshes).
4. Selecting an app reveals hidden items and attempts virtual activation.
5. A longer rehide delay is scheduled for search flow.

### Automation Triggers (Battery, App Launch, WiFi, Focus, Hover)
1. Trigger service detects event.
2. MenuBarManager.showHiddenItemsNow() is called with trigger type.
3. If auth is required, event will be blocked.
4. Auto-rehide scheduled unless pinned.

## State Machines

### App Lifecycle

```mermaid
stateDiagram-v2
  [*] --> Launching
  Launching --> DeferredUISetup: MenuBarManager init
  DeferredUISetup --> UIReady: status items created
  UIReady --> Running: services configured
  Running --> Terminating: quit
  Terminating --> [*]
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| Launching | App process starts | main.swift, AppDelegate | MenuBarManager init |
| DeferredUISetup | UI setup delayed for WindowServer readiness | deferredUISetup() | status items ready |
| UIReady | Status items exist, settings loaded | setupStatusItem() | services configured |
| Running | Normal operation | triggers, menu, hotkeys | quit |
| Terminating | App is exiting | NSApplication.terminate | process ends |

### Hide/Show State (HidingService)

```mermaid
stateDiagram-v2
  [*] --> Expanded
  Expanded --> Hidden: hide()
  Hidden --> Expanded: show()
  Expanded --> Hidden: toggle() + auto-rehide
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| Expanded | Hidden icons are visible | delimiter length = expanded | hide()/toggle() |
| Hidden | Icons are pushed off-screen | delimiter length = collapsed | show()/toggle() |

### Search Window

```mermaid
stateDiagram-v2
  [*] --> Closed
  Closed --> AuthCheck: toggle (if auth required)
  AuthCheck --> Opening: auth ok
  AuthCheck --> Closed: auth failed
  Opening --> Open: window shown
  Open --> Closing: lose focus or dismiss
  Closing --> Closed
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| Closed | No search window | default | toggle() |
| AuthCheck | Optional Touch ID gate | toggle() | auth ok/failed |
| Opening | Window created or reused | createWindow() | makeKeyAndOrderFront |
| Open | Search active, triggers suspended | window visible | resign key / dismiss |
| Closing | Window hides, triggers resume | close() | Closed |

### Automation Reveal (Triggers)

```mermaid
stateDiagram-v2
  [*] --> Monitoring
  Monitoring --> Triggered: app/battery/focus/wi-fi/hover
  Triggered --> Revealing: showHiddenItemsNow()
  Revealing --> AutoRehide: scheduleRehide()
  AutoRehide --> Hidden: delay elapsed
  AutoRehide --> Expanded: pinned by user
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| Monitoring | Triggers active | services running | trigger event |
| Triggered | Event detected | TriggerService etc | reveal call |
| Revealing | Hidden icons shown | HidingService.show() | schedule rehide |
| AutoRehide | Timer running | scheduleRehide() | hide/pin |

### Onboarding

```mermaid
stateDiagram-v2
  [*] --> NotStarted
  NotStarted --> Showing: first launch
  Showing --> Completed: user finishes
  Completed --> [*]
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| NotStarted | First launch | hasCompletedOnboarding = false | show onboarding |
| Showing | Welcome flow visible | showOnboardingIfNeeded() | complete |
| Completed | No onboarding | hasCompletedOnboarding = true | none |

### Auth Gate (Touch ID / Password)

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Prompting: auth required
  Prompting --> Authorized: success
  Prompting --> Denied: failure/cancel
  Denied --> LockedOut: too many failures
  LockedOut --> Idle: lockout expires
  Authorized --> Idle: continue flow
```

| State | Meaning | Entry | Exit |
|---|---|---|---|
| Idle | No auth in progress | default | reveal request |
| Prompting | LAContext in progress | authenticate() | success/fail |
| Authorized | Reveal allowed | auth ok | continue flow |
| Denied | Reveal blocked | auth failed | rate-limit check |
| LockedOut | Temporary block | max failures hit | timer expires |

## Persistence

Settings and profiles are stored as JSON in Application Support:
- Settings: `~/Library/Application Support/SaneBar/settings.json`
- Profiles: `~/Library/Application Support/SaneBar/profiles/*.json`

Profiles are individual files; the service enforces a max of 50 profiles.

## Concurrency Model

- UI and services are mostly `@MainActor` to avoid NSStatusItem threading issues.
- Background work (caches, timers, monitoring) is driven by Tasks and Combine.
- Accessibility caching uses async refresh to keep Find Icon responsive without blocking UI.

## Permissions and Privacy (What is actually used)

- Accessibility: required for menu bar item discovery and interaction.
- Apple Events: required for AppleScript commands.
- LocalAuthentication: Touch ID/password gating for hidden icons.
- CoreWLAN: WiFi SSID triggers.
- Focus Mode: reads local Focus Mode files for name detection.
- Launch at Login: SMAppService.

See `PRIVACY.md` for details and rationale.

## Updates and Distribution

- Sparkle is used for updates (appcast in Info.plist).
- Update feed: `https://sanebar.com/appcast.xml`.
- Release builds produce a notarized DMG; downloads are hosted via Cloudflare R2 and `dist.sanebar.com`.
- DMGs are never committed to GitHub.

## Build and Release Infrastructure

- **SaneProcess integration**: `.saneprocess` in the project root marks this as a SaneProcess-managed project.
- **DMGs**: uploaded to Cloudflare R2 bucket `sanebar-downloads` (never committed to GitHub).
- **Appcast**: Sparkle reads `SUFeedURL` from `SaneBar/Info.plist` → `https://sanebar.com/appcast.xml`.
- **Sparkle key**: `7Pl/8cwfb2vm4Dm65AByslkMCScLJ9tbGlwGGx81qYU=` (shared across all SaneApps).
- **Release workflow**: see DEVELOPMENT.md § Release Process and ARCHITECTURE.md § Operations & Scripts Reference.

## Error Handling and Recovery

- Accessibility permission changes are monitored and broadcast.
- HidingService and SearchService guard against nil status items and missing permissions.
- Authentication is rate-limited after repeated failures.
- Deferred UI setup avoids crashes when WindowServer is not ready.

## Testing Strategy

- Unit tests live under `Tests/`.
- Primary entry point for verification: `./scripts/SaneMaster.rb verify`.
- Search/trigger flows are largely integration-tested via MenuBarManager + services.

## Icon Moving Pipeline

### Why CGEvent Cmd+Drag (There Is No Alternative)

There is **no Apple API** for programmatic menu bar icon positioning. This was verified exhaustively:

| Approach | Result |
|----------|--------|
| `kAXPositionAttribute` (AX) | Read-only for menu bar items |
| `NSStatusItem.preferredPosition` | Does not exist |
| UserDefaults `NSStatusItem Preferred Position` | macOS ignores manual writes |
| `AXUIElementSetAttributeValue` | Returns error for status items |
| WWDC sessions | Zero results on this topic |

**Every app that moves icons uses the same hack:** simulate Cmd+drag via CGEvent.
Common approaches include CGEvent + dual event taps with retries, private APIs (which break across macOS versions), or simply not moving icons at all.

Sources: [NSStatusItem docs](https://developer.apple.com/documentation/appkit/nsstatusitem)

### Three-Zone Architecture

Icons live in three zones separated by two NSStatusItem delimiters:

```
[Always-Hidden zone] [AH separator] [Hidden zone] [Main separator] [Visible zone] [System items]
     ← leftmost                                                              rightmost →
```

- **Visible:** Right of main separator. Always shown.
- **Hidden:** Between separators. Shown on click/hover, auto-rehidden.
- **Always-Hidden:** Left of AH separator. Only shown via Find Icon window.

NSStatusItems grow **leftward** — right edge stays fixed, left edge extends. When hidden (length=10000), items are pushed far off-screen left (~x=-3349).

### How Icon Moving Works

**Orchestrator:** `MenuBarManager+IconMoving.swift`
**Drag engine:** `AccessibilityService+Interaction.swift` (`performCmdDrag`)

#### Move sequence:
1. **Expand** — `showAll()` shield pattern toggles both separators to visual size. Required because the 10000px separator physically blocks Cmd+drag in both directions.
2. **Wait** — 300ms for macOS relayout (500ms hits auto-rehide).
3. **Find icon** — AX scan for icon frame by bundle ID.
4. **Calculate target** — Direction-dependent:
   - **To visible:** `max(separatorRightEdge + 1, mainIconLeftEdge - 2)` — just left of SaneBar icon
   - **To hidden:** `max(separatorOrigin - offset, ahSeparatorRightEdge + 2)` — right of AH separator
   - **AH-to-hidden:** Right of AH separator (uses `moveIconFromAlwaysHiddenToHidden`)
5. **Cmd+drag** — 16-step CGEvent drag over ~240ms with cursor hidden, grab at icon center (`midX`).
6. **Verify** — Re-read AX frame, check icon landed on expected side of separator.
7. **Retry** — If verification fails, one retry with updated grab point.
8. **Restore** — `restoreFromShowAll()` + `hide()` to collapse separators back.

#### Key files:

| File | Role |
|------|------|
| `Core/MenuBarManager+IconMoving.swift` | Orchestration, separator reading, zone routing |
| `Core/Services/AccessibilityService+Interaction.swift` | `moveMenuBarIcon()`, `performCmdDrag()`, verification |
| `Core/MenuBarManager.swift` | `lastKnownSeparatorX` cache, `isMoveInProgress` flag |
| `UI/SearchWindow/MenuBarSearchView.swift` | Zone-aware context menus, `appZone()` classifier |
| `UI/SearchWindow/SearchWindowController.swift` | `isMoveInProgress` guards on window close |
| `Tests/IconMovingTests.swift` | 56 regression tests |

### Known Fragilities

1. **First drag sometimes fails** — timing between `showAll()` completing and icons becoming draggable.
2. **Wide icons (>100px)** may need special grab points.
3. **AH-to-Hidden verification is too strict** when separators are flush (both at same X). Move works visually but verification reports failure.
4. **Separator reads -3349** during blocking mode — mitigated by `lastKnownSeparatorX` cache.
5. **Re-hiding after move** can undo the move if macOS hasn't reclassified the icon yet.
6. **This will always be fragile.** Ice has the same open bugs (#684). Accept it and add retries.

### What We Tried That Didn't Work

| Attempt | Why It Failed |
|---------|---------------|
| `show()` instead of `showAll()` | Doesn't trigger proper relayout, icons stay off-screen |
| Target = `separatorX + offset` (fixed overshoot) | Overshoots past SaneBar icon into system area |
| Only expanding for move-to-visible | Move-to-hidden also blocked by 10000px separator |
| No AH boundary clamping | Move-to-hidden overshoots past AH separator |
| 30ms drag timing (6 steps × 5ms) | macOS ignores — too fast for CGEvent to register |
| Implementing "fixes" from audit without verifying bugs exist | Regressed working code (Feb 8 incident) |

## Risks and Tradeoffs

- The hide/show technique relies on NSStatusItem length behavior; macOS changes could affect it.
- Icon moving uses CGEvent Cmd+drag simulation — inherently fragile, may break on macOS updates. No alternative exists.
- Menu bar spacing uses private defaults keys (system-wide effect, logout usually required).
- Accessibility permission is mandatory for most features (including icon moving).
- Focus Mode detection depends on local system files that may change across macOS versions.

---

## Operations & Scripts Reference

After consolidation (Feb 2026), ~32 active scripts across 4 locations. Dead copies and superseded CI scripts removed.

### SaneBar Project Scripts (`scripts/`)

| Script | Purpose | Usage |
|--------|---------|-------|
| `SaneMaster.rb` | Bash wrapper — delegates to SaneProcess infra, falls back to standalone | `./scripts/SaneMaster.rb <command>` |
| `SaneMaster_standalone.rb` | Minimal build tool for external contributors (no infra dependency) | `ruby scripts/SaneMaster_standalone.rb build` |
| `qa.rb` | Pre-release QA: syntax checks, version consistency, URL reachability | `ruby scripts/qa.rb` |
| `button_map.rb` | Maps every UI button/toggle to its action handler | `ruby scripts/button_map.rb` |
| `trace_flow.rb` | Traces code path from a function name to its handlers | `ruby scripts/trace_flow.rb toggleHiddenItems` |
| `marketing_screenshots.rb` | Automates app screenshots for marketing | `ruby scripts/marketing_screenshots.rb --list` |
| `verify_crypto_payment.rb` | Verifies crypto transactions (BTC/SOL/ZEC), sends download links | `ruby scripts/verify_crypto_payment.rb` |
| `generate_download_link.rb` | Generates signed download URLs with expiration | `ruby scripts/generate_download_link.rb` |
| `check_outreach_opportunities.rb` | Scans GitHub for outreach/collaboration opportunities | `ruby scripts/check_outreach_opportunities.rb` |
| `functional_audit.swift` | Runtime functional audit of app behavior | `swift scripts/functional_audit.swift` |
| `verify_ui.swift` | UI verification checks | `swift scripts/verify_ui.swift` |
| `stress_test_menubar.swift` | Menu bar stress test | `swift scripts/stress_test_menubar.swift` |
| `overflow_test_menubar.swift` | Menu bar overflow edge cases | `swift scripts/overflow_test_menubar.swift` |
| `uninstall_sanebar.sh` | Clean uninstall script for users | `bash scripts/uninstall_sanebar.sh` |

### SaneMaster Commands (via SaneProcess)

The wrapper at `scripts/SaneMaster.rb` delegates to `SaneProcess/scripts/SaneMaster.rb`. Full help: `./scripts/SaneMaster.rb help`.

| Category | Commands | Purpose |
|----------|----------|---------|
| **build** | `verify`, `clean`, `lint`, `release`, `release_preflight`, `appstore_preflight` | Build, test, release pipeline, App Store compliance |
| **sales** | `sales`, `sales --products`, `sales --month`, `sales --fees` | LemonSqueezy revenue reporting |
| **check** | `verify_api`, `dead_code`, `deprecations`, `swift6`, `test_scan`, `structural` | Static analysis, API verification |
| **debug** | `test_mode` (tm), `logs --follow`, `launch`, `crashes`, `diagnose` | Interactive debugging, crash analysis |
| **ci** | `enable_ci_tests`, `restore_ci_tests`, `fix_mocks`, `monitor_tests`, `image_info` | CI/CD test helpers |
| **gen** | `gen_test`, `gen_mock`, `gen_assets`, `template` | Code generation, mocks, assets |
| **memory** | `mc`, `mr`, `mh`, `mcompact`, `mcleanup`, `session_end`, `reset_breaker` | Cross-session memory, circuit breaker |
| **env** | `doctor`, `health`, `bootstrap`, `versions`, `reset`, `restore` | Environment setup, health checks |
| **export** | `export`, `md_export`, `deps`, `quality` | PDF export, dependency graphs |

### Shared Infrastructure (SaneProcess `scripts/`)

These live in `SaneProcess/scripts/` and serve all SaneApps projects.

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `release.sh` | Full release pipeline: build + sign + notarize + DMG + Sparkle + R2 + appcast | `release.sh --project $(pwd) --full --version X.Y.Z` |
| `sane_test.rb` | Unified test launch: kill → build → deploy → launch → logs | `sane_test.rb SaneBar` (uses Mac Mini by default) |
| `license_gen.rb` | Generate customer license keys | `ruby license_gen.rb <email>` |
| `version_bump.rb` | Bump version strings across project files | `ruby version_bump.rb 2.2.0` |
| `contamination_check.rb` | Detect cross-project reference leaks | `ruby contamination_check.rb --all` |
| `link_monitor.rb` | Monitor critical URLs (checkout, download, website) | Runs as LaunchAgent daemon |
| `scaffold.rb` | Create new app project with SaneApps structure | `ruby scaffold.rb NewApp` |
| `memory_audit.rb` | Find unfixed bugs/unresolved issues in Memory MCP | `ruby memory_audit.rb` |
| `validation_report.rb` | Measure SaneProcess productivity metrics | `ruby validation_report.rb` |
| `publish_website.sh` | Deploy website to Cloudflare Pages | `bash publish_website.sh` |
| `appstore_submit.rb` | App Store Connect submission (JWT, upload, polling) | `ruby appstore_submit.rb` |
| `qa_drift_checks.rb` | Catch quality drift between SaneProcess and projects | `ruby qa_drift_checks.rb` |
| `weaken_sparkle.rb` | Patch Sparkle dylib for App Store builds | `ruby weaken_sparkle.rb` |

### Mac Mini & Automation

Mini scripts live in `SaneProcess/scripts/mini/` (source of truth) and `infra/scripts/` (deployed copies).

| Script | Schedule | Purpose |
|--------|----------|---------|
| `mini-nightly.sh` | 2 AM daily | Git sync + build all apps + run tests + system health |
| `mini-train.sh` | 3 AM daily | MLX LoRA fine-tuning |
| `mini-build.sh` | On-demand | Remote build trigger |
| `mini-test-install.sh` | On-demand | DMG mount + verify (customer-experience test) |
| `mini-sync.sh` | On-demand | Git sync across all repos |
| `mini-report.sh` | On-demand | Fetch nightly report from Mini |
| `mini-training-report.sh` | On-demand | Fetch training report from Mini |

Automation scripts (`SaneProcess/scripts/automation/`): `nv-audit.sh`, `nv-relnotes.sh`, `nv-tests.sh`, `nv-buildlog.sh`, `morning-report.sh`, `start-workday.sh` — see `automation/README.md`.

### SOPs

**License key generation:** `ruby SaneProcess/scripts/license_gen.rb <email>`. Keys use HMAC-SHA256 with a salt stored in the script. Format: `SANE-XXXX-XXXX-XXXX-XXXX`. See Serena memory `license-key-prefreemium-sop` for full procedure.

**Release process:** See `SaneProcess/templates/RELEASE_SOP.md`. Summary: bump version → `release_preflight` → `release.sh --full --deploy` → verify appcast → monitor.

**Customer email:** See `check-inbox.sh` in `infra/scripts/`. Commands: `check`, `review <id>`, `reply <id> <body_file>`, `compose`, `resolve`.
