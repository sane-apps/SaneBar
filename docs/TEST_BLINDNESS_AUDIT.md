# SaneBar Test-Blindness Audit

Audit date: 2026-06-24. Scope: all 153 SaneBar GitHub issues cross-checked against
the test suite. Static source reading + the existing runtime probes; no build/run.
This is the **tracking doc for the test-remediation program** — keep it current as
blind families get a real runtime gate.

> 🚩 **Headline:** The SaneBar suite is **behavior-blind.** ~210 `RuntimeGuard*XCTests`
> methods carry **~2,000+ `source.contains("…")` / `String(contentsOf:)` assertions**
> that check code **structure, not runtime behavior** — a real regression sails
> through them green. **~85–90% of the menu-bar / geometry / recovery assertion *mass*
> is source-fingerprint.** That blindness is why broken builds shipped "tests green."
> Genuine runtime-behavior coverage is concentrated in **~5 Ruby probes**
> (`live_zone_smoke`, `wake_layout_probe`, `startup_layout_probe`,
> `customer_ui_action_sweep`, `runtime_smoke`) — a low-single-digit % of total
> assertions. FM-1 is now **default-on + release-blocking and de-blinded** (asserts the
> real zone delta of the move, not the old unsatisfiable live-frame proxy — see §6);
> FM-2 is still **env-flag-gated and absent from the default run.**

See also `docs/GEOMETRY_TRUST_REVIEW_2026-06-10.md` (the geometry/recovery root-cause
families) and the NO BLIND TESTS testing rule this audit drove (DEVELOPMENT.md § Testing).

---

## 1. Test-surface taxonomy

Three buckets, by what each actually proves. The `RuntimeGuard` name is a misnomer:
those files guard **source**, not runtime.

### Bucket A — SOURCE-FINGERPRINT GUARDS (blind to behavior)

`Tests/RuntimeGuard*XCTests.swift` + a few contract files. They `String(contentsOf:)`
a product `.swift`/config file off disk and assert `source.contains("…")` /
`XCTAssertFalse(source.contains(…))` / source ordering. They **never instantiate or
drive the app.** A behavior can be 100% broken and these stay green; the literal can
rot while the test stays green if the magic substring survives by accident. Legitimate
role: "don't delete the fix" shipping-hygiene tripwires — **not proof the fix works.**

| File | tests | string-match assertions | Nature |
|---|---|---|---|
| RuntimeGuardRepoGeometryXCTests.swift | 49 | ~385 | gitignore / project.yml / SaneUI pin / Info.plist / onboarding copy |
| RuntimeGuardMoveQueueXCTests.swift | 31 | ~268 | move-queue *source* shape (not runtime queue behavior) |
| RuntimeGuardStartupRecoveryXCTests.swift | 21 | ~264 | startup-recovery *source* shape |
| RuntimeGuardQAAndLicensingXCTests.swift | 16 | ~250 | qa.rb / licensing source strings |
| RuntimeGuardSettingsSurfaceXCTests.swift | 15 | ~200 | settings-view source strings |
| RuntimeGuardQASmokeXCTests.swift | 4 | ~182 | qa smoke *script source* presence |
| RuntimeGuardMoveActivationXCTests.swift | 30 | ~182 | move/activation source shape |
| RuntimeGuardAppleScriptMoveXCTests.swift | 15 | ~164 | AppleScript move command source |
| RuntimeGuardSearchWindowIdleXCTests.swift | 9 | ~113 | search-window idle source |
| CustomerUIActionContractXCTests.swift | 10 | ~70 | sweep-script contract strings |
| RuntimeGuardAppleScriptActivationXCTests.swift | 6 | ~47 | AppleScript activation source |
| GeneralSettingsSimplificationXCTests.swift | 24 | ~12 | mostly source strings |

**Bucket A total: ~210 test methods, ~2,000+ behavior-blind string-match assertions** —
the single largest assertion mass in the suite and the central blind spot.

### Bucket B — PURE UNIT TESTS (real assertions, no live app)

Test Swift policy/pure functions in isolation with real assertions, mocks, and codable
round-trips. They prove "given these inputs the policy returns X"; they do **not** prove
the live `NSStatusItem` produces those numbers on a real Mac. The gap between the unit's
*input model* and the real runtime's *actual geometry* is exactly where the
#136/#155/#157/#166/#168 family lived. Examples: `MenuBarDriftIntentPolicyTests`,
`MenuBarAutomaticMoveGateTests`, `IconMovingGeometryRegressionTests`,
`MenuBarVisibilityFlapDetectorTests`, `MenuBarManagerRecoveryPolicyTests`,
`StatusBarController*Tests`, `MenuBarAppearance*Tests`, `Persistence*Tests`,
`AccessibilityService*Tests`, `HidingServiceTests`. Maybe ~10–15% of methods — strong
locally, blind to the input/runtime gap.

### Bucket C — RUNTIME PROBES (launch/drive the live app, assert observed behavior)

Ruby harnesses run on the maintainer's build machine. They launch the signed app, drive it via the AppleScript
dictionary, and read back the **`layout snapshot`** introspection command
(`Core/Services/LayoutSnapshotCommand.swift`) — a JSON dump of live geometry. **This is
the only behavior-real layer.** By assertion *count* it is a rounding error
(low-single-digit %), yet it is the ONLY layer that can catch the recurring
geometry/recovery regressions.

`layout snapshot` exposes the assertable signals: `hidingState`, `separatorBeforeMain`,
`alwaysHiddenBeforeSeparator`, `mainStatusItemLeftEdgeX`, `separatorOriginX/RightEdgeX`,
`mainRightGap`, `mainNearControlCenter`, `mainWindowValid/separatorWindowValid`,
`startupItemsValid`, `possibleSystemMenuBarSuppression`, `licenseIsPro`, and the
FM root-cause fields `alwaysHiddenSeparatorLength` (10000 = genuinely hidden, ~14 =
revealed), `alwaysHiddenSeparatorLiveFrameReadable`, `persistedMainPreferredPosition`,
`persistedSeparatorPreferredPosition`.

| Probe | What it actually drives & asserts |
|---|---|
| `Scripts/live_zone_smoke.rb` (+ `lib/live_zone_smoke_*`) | Real moves: `move_and_verify` → issues the move command → `wait_for_zone` → `assert_zone_stays_stable_after_move` (re-check the move did not silently drift back). Browse / Second-Menu-Bar click + reaction verify. Appearance-overlay **pixel** tint check (`assert_customer_visible_top_strip_tint!`). RSS/CPU budget. **FM-1 gate** (default-on + release-blocking via project_qa_runtime_preflight; opt-out `SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1`): stage SBF into Always Hidden, drive to genuine hidden separator (length ~10000), then assert via real zone delta that AH→Visible/AH→Hidden actually leaves Always Hidden and stays. De-blinded — see §6. |
| `Scripts/startup_layout_probe.rb` | Seeds poisoned/dirty prefs, quit/relaunch, snapshots at T+2s/T+5s. Issue-tagged cases **#157 dirty-reboot recovery**, **#155 Always-Hidden dirty replay**, poisoned-backup restore, currentHost cleanup, autoRehide. `move_icon_and_expect!` asserts observed zone == expected. 10-min resource soak. |
| `Scripts/wake_layout_probe.rb` | Display sleep/wake; `assert_cursor_stable!`, `assert_visible/hidden_zone_persistence!`, `assert_main_right_gap_stable!`, `BLOCKED_LOG_PATTERNS` (e.g. "Status item remained off-menu-bar"). **FM-2 gate** (env `SANEBAR_WAKE_PROBE_EXPLICIT_DIVIDER_SURVIVAL`): seeds a divider FAR from Control Center, asserts persisted positions don't reanchor toward CC. |
| `Scripts/customer_ui_action_sweep.rb` | Two genuine runtime probes: `exercise_hover_auto_rehide_runtime_probe` (hover→reveal→assert rehide) and `exercise_license_clipboard_paste_runtime_probe` (paste→assert field populated). The rest of its manifest is fingerprint-grade. |
| `Scripts/runtime_smoke.rb` | Lightweight smoke + log-regex scan + a **manual** human checklist (SMB vs Icon Panel stuck-open). |

---

## 2. Per-issue classification (merged from the 4 batch audits)

Gate vocabulary: **RUNTIME-GATED** = drives the real app, reproduces failure + success.
**PARTIAL** = a real driver exists but doesn't hit this exact trigger / asserts a weaker
signal. **UNIT-ONLY** = pure logic test. **FINGERPRINT-ONLY** = only `source.contains`
stands between the bug and green. **NO-GATE** = nothing reproduces it at runtime.

### Issues #1–#69 (behavioral subset; the rest are feature/build/docs/noise → n/a)

| Issue | Failure mode | Family | Gate | Classification | Runtime repro needed |
|---|---|---|---|---|---|
| #6/#8/#29 | Find Icon window slow to populate | perf | idle/perf budget in live_zone_smoke; SearchWindow logic units | PARTIAL (perf budget) / UNIT | Open Find Icon w/ 25+ items, measure time-to-first-result |
| #11 | Icons auto-reveal on switch to non-primary display | R7 display | wake covers wake; no display-SWITCH rehide assert | NO-GATE | Hide, switch active display, assert hidden zone stays collapsed |
| #15 | Divider/zone customization not visible in Settings | R4 settings | settings-surface `source.contains` | FINGERPRINT-ONLY | Open Settings→Appearance, assert divider controls render & reachable |
| #18 | Hiding icons no-op | R2 browse-rehide | live_zone_smoke toggle + collapse verify | RUNTIME-GATED | — |
| #20/#34 | Tint not applied in dark mode | appearance | pixel check **only** behind `…REQUIRE_APPEARANCE_TINT_PIXELS=1` | RUNTIME-GATED (flag-gated) / else NO-GATE | Enable tint dark mode, assert orange pixels persist past boot |
| #21 | Icons hidden behind notch | compat/notch | unit only; no notch-overflow visibility assert | UNIT-ONLY | Notched internal display, assert no managed icon under cutout |
| #22 | Search-opened menu closes too soon | R2 / search-idle | search-idle source guard | FINGERPRINT-ONLY | Open item menu from Find Icon, assert stays open until dismiss |
| #32/#48 | After update positions lost / all collapsed | R3 persistence | startup_layout_probe geometry restore | RUNTIME-GATED | — (verify pre-update zone restore) |
| #35/#56 | Items don't stay/move to Visible | R1 move | move_and_verify + stability | RUNTIME-GATED | — |
| #45/#52 | Visible icons vanish (after update / cursor-enter) | R3 / R2 flap | flap detector + post-move stability | RUNTIME-GATED / partial (cursor-enter) | Cursor into bar repeatedly, assert visible set survives |
| #47 | Update moved hidden → always-hidden | R3 zone-migration | unit migration tests; no migration-preserves-zone runtime gate | UNIT-ONLY | Seed hidden, run migration, assert items stay hidden |
| #50/#61/#62 | "Show hidden in second bar" not honored | R4 / second-bar | browse-mode anchor assert | RUNTIME-GATED | Verify hidden render on SECOND strip, not inline-left |
| #57 | Wrong hotkey label | R4 label | `source.contains(label)` | FINGERPRINT-ONLY | Bind shortcut, assert displayed accelerator matches |
| #60 | "Always Show on External Monitor" ignored | R7 display | probe only SETS the flag; never asserts external strip | NO-GATE | External display, assert external bar independent of primary |
| #64 | Rounded corners clip bar edges | appearance | none | NO-GATE | Enable rounded corners, assert no edge clipping |
| #69 | Clicking icons in 2nd bar / Icon Panel no popover | R1 / browse-click | browse activation assert | RUNTIME-GATED | Verify the target's popover/menu actually opens |

### Issues #70–#99

| Issue | Failure mode | Family | Gate | Classification | Runtime repro needed |
|---|---|---|---|---|---|
| #70 | Drag/Ctrl-click→Visible no-op; reinstall flips visibles→hidden | R1 + R3 | move_and_verify; startup probe | RUNTIME-GATED | Ensure a Ctrl-click→Visible variant in the move lane |
| #71 | Helper-hosted / nil-bundle-ID extra (Little Snitch) never enumerated | R5 detection | mock-based unit only | UNIT-ONLY | Live probe enumerating a nil-bundle-ID status item |
| #72 | Layout not persisted across quit/logout/reboot | R3 | startup probe + healthy snapshot | RUNTIME-GATED | — |
| #73 | Restart moves all visible→hidden | R3 | startup poisoned/dirty-reboot recovery | RUNTIME-GATED | — |
| #74 | No drag; no Little Snitch; apps invisible after 2nd-bar click | R1+R5+R2 | move gated; detection/2nd-bar not | PARTIAL | Live 2nd-bar click that asserts the app icon becomes visible |
| #75 | After update, click doesn't hide (external-monitor setting blocked) | R4 / R7 | unit toggle only | UNIT-ONLY | Set skip-hide-for-external ON, click, assert items hide |
| #76 | Browse "Grant Access" loop; AX grant not seen | recovery / perms | none | NO-GATE | AX re-check probe asserting Browse panel exits the grant gate |
| #77 | 2nd-bar AH/hidden→Visible silently fails (offscreen donor) | R1 (offscreen donor) | move_and_verify, but donor-with-no-visible-item not explicit | PARTIAL | Move lane where donor has NO live status item |
| #78 | After 2.1.6, all visible→hidden ("Move verification failed") | R3 + R1 | startup flip + move-verify | RUNTIME-GATED | — |
| #79 | Every v2.1.x update resets to control-center-only | R3 | startup poisoned/dirty-reboot recovery | RUNTIME-GATED | — (real trigger is #92 display-disconnect, not covered) |
| #85 | Light-mode contrast unreadable | appearance | dark-mode units; light mode de-scoped | UNIT-ONLY | Contrast assert on Browse panel (if light mode resumes) |
| #86 | Removing "hide" divider makes trigger icon vanish, no recovery | recovery | unit only | UNIT-ONLY | Delete hide divider, relaunch, assert trigger reappears |
| #87 | 2nd-bar: dead clicks; mouse-jump; dropdown closes early | R2 | cursor-restore is `source.contains`-guarded | FINGERPRINT-ONLY | 2nd-bar click asserts menu opened AND cursor returned |
| #89 | Apps pulled from hidden not remembered after restart | R3 | startup relaunch + healthy snapshot | RUNTIME-GATED | — |
| #91 | v2.1.12 shows NO icons (enumeration blackout) | R3 / enumeration | move needs icons present; sweep reads "Found N" | PARTIAL (weak) | Launch assert: live icon count > 0 / matches system count |
| #92 | Update resets **when external monitor disconnected during update** — STILL RECURRING | R3 + R7 display | same-display recovery only; NEITHER probe simulates display-disconnect across upgrade | NO-GATE (real trigger) | Seed multi-display → remove display → relaunch single-display → assert not reset |
| #93 | Can't move to Visible ("Move verification failed afterX≠separatorX") | R1 | move_and_verify hidden→visible + stability | RUNTIME-GATED | — |
| #94 | Can't launch hidden app; can't move hidden→visible | R1 + activation | move gated; launch/activation `source.contains` | PARTIAL | Trigger "launch hidden app", assert target activates frontmost |
| #95 | Search-window clicks dead; icons drift to AH | R1 + R2 | move-verify + stability catch drift; search-click not | PARTIAL | Click search result, assert click reached target (menu opened) |

### Issues #100–#129

| Issue | Failure mode | Family | Gate | Classification | Runtime repro needed |
|---|---|---|---|---|---|
| #101 | 2nd-bar clicks no-op / icons vanish / SMB sizing | R2 | exercise_browse_modes → activation reaction verify | RUNTIME-GATED | — |
| #102 | "Second Menubar" option does nothing | R4 | none (sweep is `source.contains`) | FINGERPRINT-ONLY | Set left-click=Open SMB, click, assert SMB window appears |
| #105 | SMB unresponsive; click flips zone | R2 (dup #101) | SMB click + zone-stability assert | RUNTIME-GATED | — |
| #106 | Browse drag/right-click move hidden→visible fails | R1 | move_and_verify + browse activation | RUNTIME-GATED | — |
| #107 | Tahoe: no icon/separator renders; shortcuts dead | recovery / compat | dirty-reboot valid-window wait asserts both attach | PARTIAL | Tahoe-supplemental build: assert both items attach (still repro 2.1.34) |
| #108 | No menu-bar apps after launch | R3 / startup | healthy-snapshot asserts visible present | RUNTIME-GATED | — |
| #109 | Browse list mismatches live bar; drag fails | R1 | move/browse off live zones | RUNTIME-GATED | — |
| #110 | Dock icon appears during background ops; steals focus | R7 dock-policy | only `source.contains('Show app in Dock')` | FINGERPRINT-ONLY | Accessory-mode soak, assert `activationPolicy` stays `.accessory` |
| #111 | Profiles don't restore; visible collapse to hidden | R3 / profile | reset half gated; profile-load half not | PARTIAL | Save→mutate→load profile, assert zones match saved snapshot |
| #112 | Save→load profile → no change | R3 / profile | none (`source_line('profiles')`) | FINGERPRINT-ONLY | Live save→change→load→verify zones |
| #113 | After upgrade, all visible→hidden | R3 | poisoned-backup restore + zone snapshot | RUNTIME-GATED | — |
| #114 | Icon+separator left of Control Center every login | recovery / startup | current-width backup beats ordinal seeds + gap stability | PARTIAL | Verify probe seeds the left-of-CC ordinal poison (repro 2.1.33) |
| #115/#121/#125 | Icons reset **while app is running** (idle drift) | R3 | wake + startup gated; no idle-soak reset probe | PARTIAL | Long idle soak w/ periodic zone snapshots; assert no spontaneous reset |
| #116 | Right-click browse flashes; focus jumps | R2 / focus | browse activation + focus-integrity smoke | RUNTIME-GATED | — |
| #117 | hidden→visible beachballs; wrong CC sibling moved | R1 identity | move_and_verify exact target id | PARTIAL | Move A, assert A (not sibling B) changed zone; no main-thread stall |
| #122 | Custom tint flips to **black when another app foregrounds** | appearance | pixel check exists but transition-gated, wrong trigger | PARTIAL (wrong trigger) | Apply tint, raise a foreground app, assert tint pixels unchanged |
| #123 | Wake → all icons Visible | R3 | wake hidden-survival assert | RUNTIME-GATED | — |
| #124 | Layout reverts to all-visible (external monitor) | R3 | wake + startup; display-change partial | PARTIAL | Multi-display attach/detach + idle soak |
| #126 | SaneBar icon vanishes; survives Reset-to-Defaults | R3 / recovery | startup recovery snapshot asserts main present | PARTIAL | Seed missing-icon state, run Reset live, assert main re-renders (2.1.36) |
| #128 | App icon + MeetingBar disappear; must force-kill | R3 | required-visible-ids asserts | PARTIAL | Seed named required-visible icon, soak, assert stays present |
| #129 | Drag main icon+divider out → **permanently lost** | R1 + R3 | none drives drag-out→recover; only `source.contains` | FINGERPRINT-ONLY | Drag icon+divider off bar, Reset/relaunch, assert main reappears (2.1.38) |

### Issues #130–#168

| Issue | Failure mode | Family | Gate | Classification | Runtime repro needed |
|---|---|---|---|---|---|
| #130 | Icon gone after morning login; only Finder relaunch fixes | R3 / recovery | #157 dirty-reboot + off-menu-bar log guard | RUNTIME-GATED | — |
| #133 (OPEN) | Status item+separator invisible on Tahoe supplemental; FrontBoard loop | recovery / compat | log guard catches symptom; no Tahoe-specific case; `source.contains` | FINGERPRINT-ONLY + partial | Drive on the affected OS build; assert visible without reconnection loop |
| #135 | Fewer items visible after relaunch/wake | R3 | wake visible-zone persistence + gap stability | RUNTIME-GATED | — |
| #136 (OPEN) | Toggle+divider jump far left after 1↔2 screen switches | R3 / recovery | gap-stability + bad-backup rejection; **NO multi-display switch driver** | PARTIAL | Switch 1→2 monitors, assert divider-to-toggle spacing healthy |
| #138 | Cannot drag Hidden→Visible; source treated off-screen | R1 | live moves + `move_icon_and_expect!` | RUNTIME-GATED | — |
| #139 | MeetingBar disappears from Visible daily/after wake | R3 | wake visible+hidden persistence | RUNTIME-GATED | — |
| #140 | Cannot move Always Hidden→Hidden/Visible | R1 / R2 | AH moves + round trips + browse + SMB | RUNTIME-GATED | — |
| #141 | RSS >1 GB after days | perf | RSS ceiling + 10-min soak | PARTIAL | Multi-day leak below soak window could pass; extend soak |
| #142 | Dark tint blinks black on launch from Spotlight/Dock | appearance / startup-timing | suppression units; steady-state pixel only | UNIT-ONLY | Cold/Spotlight launch, sample tint during first ~1s, assert no black frame |
| #143 | "Show on hover" doesn't reveal | R2 | hover→reveal runtime probe | RUNTIME-GATED | — |
| #146 (OPEN) | Auto-hide not triggering | R2 | auto-rehide-after-delay probe | RUNTIME-GATED | — |
| #147 | Dynamic items jump Shown→Hidden after wake | R3 | wake visible persistence; warmed-geometry classification | RUNTIME-GATED | — |
| #148 | Cannot paste purchased license key | license | clipboard-paste runtime probe | RUNTIME-GATED | — |
| #150 (OPEN) | Spotlight + SaneBar icons re-moved after arranging | R3 / R7 | gap-stability + persistence; no Spotlight-neighbor anchor case | PARTIAL | Arrange neighbors, relaunch/wake, assert anchors unchanged |
| #151 (OPEN) | Cursor "overtaken," icons grabbed (simulated-drag restore) | recovery / dock | `assert_cursor_stable!` (parked cursor must not move) | RUNTIME-GATED | — |
| #152 (OPEN) | Icon vanishes after location/display change; Repair no-op | R3 / recovery | recovery asserts + log guard; Repair-acts is fingerprinted | PARTIAL | Drive Repair during rapid visibility toggle, assert it produces a state change |
| #154 | Cursor jumps/freezes (2.1.63/.64) | recovery | `assert_cursor_stable!` | RUNTIME-GATED | — |
| #155 (OPEN) | Cannot move OUT of Always Hidden; later OOM | R1 + perf | startup #155 case + post-move soak; live_zone AH moves | RUNTIME-GATED | Move covered; OOM may exceed 10-min soak — extend |
| #156 (OPEN) | Icons won't move to visible after update; drop hugs edge | R1 | live moves + `move_icon_and_expect!` (landed zone) | RUNTIME-GATED | — |
| #157 (OPEN) | Icon disappears after reboot; windows off-bar (y=-22) | R3 / recovery | startup #157 dirty-reboot + off-menu-bar log guard | RUNTIME-GATED | — |
| #158 (OPEN) | Custom overlay covers Mission Control on macOS 27; nothing hidden | appearance / compat | `testSuppressesOverlayForMissionControlSurface` unit only | UNIT-ONLY | Drive on macOS 27: open Mission Control, assert overlay not drawn; change Space, assert re-hide (still broken 2.1.72) |
| #159 (OPEN) | Constant crash after 2.1.73 | recovery / crash | launch/idle probes fail on crash-loop; no crash-signature gate | PARTIAL (indirect) | Capture crash-log signature in a probe assertion |
| #160 (OPEN) | Menu unfurls/collapses on its own every few minutes | R2 / recovery | **NONE** — probes drive only intentional hover | **NO-GATE** | Idle, pointer parked away, assert hidingState stays `hidden` (still repro 2.1.80) |
| #161 (OPEN) | Settings window pops up randomly | recovery / dock | **NONE** — nothing asserts Settings is NOT auto-presented | **NO-GATE** | Idle + trigger recovery, assert Settings/onboarding window count stays 0 |
| #163 | Crash/reload loop, steals focus (fixed 2.1.76) | recovery / crash | launch/idle fail on crash-loop; no focus-ownership assert | PARTIAL | Add focus-ownership assert during passive recovery |
| #165 (OPEN) | "Icons stay hidden ~2s"; stale separator frame | R2 / recovery | hover/rehide probe; warmed-geometry classification | PARTIAL | Assert revealed state persists ≥ delay, not force-collapsed within ~2s |
| #166 (OPEN) | Dragging in second-menu-bar UI does literally nothing | R1 | AppleScript move gated; **in-panel drag gesture not driven** | NO-GATE (in-panel drag) | Drive a real drag inside the SMB/browse UI, assert persisted zone/order changes |
| #167 (OPEN) | Activated Pro license still shows "Pro Trial" | license | probes assert `licenseIsPro` truthy to run; never assert displayed tier string | FINGERPRINT/NO-GATE | Activate real Pro, assert License view renders "Pro" not "Pro Trial" |
| #168 (OPEN) | Sort order of hidden/visible icons always resets | R3 | wake/startup assert membership; **intra-zone order not asserted** | PARTIAL | Set a specific order, relaunch/wake, assert the *sequence* preserved |

n/a (non-runtime — feature/build/install/signing/Homebrew/Sparkle/docs/UX-copy/noise):
#1, #5, #7, #9, #10, #12–#14, #16, #17, #19, #23–#28, #30, #31, #33, #36–#44, #46, #49,
#53–#55, #59, #63, #65–#68, #81, #83, #84, #90, #99, #100, #103, #119, #120, #144, #164.

---

## 3. Runtime-BLIND families, ranked by live damage

Where a regression can ship **green** because no probe drives the real customer trigger.
Ordered by exposure (still-recurring / open issues first).

1. **Idle spontaneous-presentation (#160 menu auto-unfurls, #161 Settings auto-pops; meta #162).**
   **NO-GATE.** Every probe drives *intentional* actions; nothing asserts the app stays
   passive when idle. #160 still reproducing on 2.1.80. **Highest exposure.** Needs an
   idle-quiescence probe: park pointer, wait minutes, assert no expanded transition and
   zero auto-presented windows.
2. **Window-invalidation / move from genuine-hidden core (#166 in-panel drag, #165 stale
   separator, #136 multi-display jump).** The AppleScript move path is gated; the actual
   UI drag handler is not. The genuine-hidden start state IS now gated by FM-1, which is
   default-on + release-blocking and asserts a real zone delta (see note below). A dead
   in-panel drag handler / stale-frame collapse still ships green.
3. **License tier-string (#167).** The gate checks `licenseIsPro` truthiness only to decide
   whether to run Pro flows — it never asserts the rendered tier string. An activated Pro
   showing "Pro Trial" sails through. **FINGERPRINT-ONLY.**
4. **Display-disconnect-during-update persistence (#92).** THE recurring reset trigger.
   Reset is gated only for same-display upgrades; the real trigger (monitor disconnected
   *during* the update/relaunch) has **no probe at all**. Every reopen of #92 was on a
   green build. **NO-GATE for the real trigger.**
5. **Intra-zone order (#168).** Gates assert zone *membership*, never icon *sequence*.
   Membership passes while order scrambles. Still open.
6. **In-panel drag gesture (#166-UI).** Same root as #2 but called out: the thing the user
   actually touches (drag inside the panel) is never driven. **NO-GATE.**
7. **Profile save/load (#112, #111-profile-half, #102 setting→behavior wiring).** The
   save→change→load→apply-layout cycle is only `source.contains`-checked. A profile-restore
   regression ships green. **FINGERPRINT-ONLY.**
8. **Tint-on-activation (#122).** A real pixel check exists but fires on fullscreen
   transition, not on another app coming to the foreground (the actual repro). Effectively
   blind to the reported trigger. Also #142 startup-blink (no first-1s timing gate).
9. **Tahoe / macOS-27 compat (#133, #158).** Behavior is only UNIT-tested
   (Mission-Control-suppression predicate) or caught by a log-pattern symptom; the real
   invisible-icon / overlay-over-Mission-Control failures are not driven on the affected OS
   build and keep reproducing (#133 on 2.1.43, #158 on 2.1.72). Mini has no matching OS
   build — needs a Tahoe runner.

Secondary blind spots: dock-policy drift (#110, #11, #60), helper-hosted detection
(#71, #74), idle-running reset (#115/#121/#125), lost-icon + Reset-to-Defaults recovery
(#126, #129), divider-deletion recovery (#86), AX-grant loop (#76), days-long memory
leak (#141, #155 OOM — soak is only 10 min).

---

## 4. Recommended runtime-harness shape

Goal: convert each blind family into a deterministic, Mini-runnable, **fail-before /
pass-after** gate that asserts on `layout snapshot` fields (not source strings, not the
app's own zone self-report alone), and is **DEFAULT-ON** in `qa.rb`'s release path.

| Blind family | State to drive | Signal to assert (`layout snapshot`) | Fail-before / pass-after |
|---|---|---|---|
| **Idle spontaneous-presentation (#160/#161)** | Launch, park pointer far from bar, idle several minutes; also fire recovery while idle. | `hidingState` stays `hidden`; auto-presented Settings/onboarding window count == 0. | Spontaneous unfurl / auto-pop → state changes while idle → FAIL. **New probe.** |
| **Move from genuine-hidden (FM-1) / in-panel drag (#166)** | Stage icon in Always Hidden, `hide items` to genuine hidden (`alwaysHiddenSeparatorLength` > 1000); drive AH→Visible AND AH→Hidden **and** a real drag inside the SMB/browse UI. | **PRIMARY: the real zone delta** — `list icon zones` shows the fixture LEFT `alwaysHidden` and STAYED after the post-move settle (`assert_left_always_hidden_zone_delta!` + `assert_zone_stays_stable_after_move`). `alwaysHiddenSeparatorLiveFrameReadable` is **advisory only** and read solely in the contracted (length ≤ 14) window — never asserted from length 10000. Persisted order/zone reflects the drag (UI-drag driver still TODO). | Pre-fix length cap no-ops the move / icon snaps back → `move_and_verify` raises → FAIL. **Done: FM-1 is now default-on + release-blocking and asserts the real zone delta (de-blinded, see §6). UI-drag driver still TODO.** |
| **Reanchor / display-disconnect (FM-2 + #92)** | Seed `Preferred Position` FAR (main≈900, sep≈940); cold launch; drive wake, a real Space switch + app-activation, AND a display-disconnect-across-relaunch. | `persistedMain/SeparatorPreferredPosition` unchanged (±tol); `mainNearControlCenter` stays false; layout NOT reset after single-display relaunch. | Reanchor toward CC / reset on disconnect → positions drift → FAIL. **Make FM-2 default-on; add disconnect + Space axes.** |
| **License tier-string (#167)** | Activate a real Pro license. | License view renders "Pro" (not "Pro Trial"); `licenseIsPro == true`. | Label wrong while boolean true → string assert → FAIL. |
| **Intra-zone order (#168)** | Set a specific icon sequence; relaunch + wake. | The *ordered sequence* per zone preserved, not just set membership. | Order scrambles → sequence assert → FAIL. |
| **Profile save/load (#112)** | Save profile, mutate layout, load profile — all live. | Post-load zone membership + order match the saved snapshot. | Load no-ops → mismatch → FAIL. |
| **Tint-on-activation (#122/#142)** | Custom tint; raise a foreground app; also cold/Spotlight launch. | `assert_customer_visible_top_strip_tint!` pixels unchanged on activation; no transient black frame in first ~1s. | Tint flips black → pixel check → FAIL. |
| **Window-invalid recovery (#126/#129/#152)** | Mid-session force an invalid status-item window frame (off-screen/zero), or drag main+divider off bar; trigger Repair/Reset/relaunch. | `mainWindowValid`/`separatorWindowValid` recover true; `startupItemsValid` true; main re-renders. | Recovery no-ops → window stays invalid → FAIL. |
| **Tahoe/macOS-27 compat (#133/#158)** | Drive on the affected OS build (needs a Tahoe runner). | Status item visible without reconnection loop; overlay not drawn over Mission Control; items re-hide on Space change. | Invisible icon / overlay leak → FAIL. |

Cross-cutting:
- **FM-1 is now default release-blocking** (project_qa_runtime_preflight enables it unless
  `SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1`). **Still TODO: make FM-2 default
  release-blocking** — drop its env-flag opt-in (or have the release flow export it
  unconditionally). Today a default `qa.rb` run can be all-green while FM-2's blind spot
  is never exercised.
- **Add a multi-display and a real Space-change axis** to the move / persistence / tint gates.
- **Add ≥1 real third-party menu-extra** alongside the `com.sanebar.sharedfixture` fixture
  for identity/resolution coverage (kept tolerant so it doesn't flake the release).
- **Automate the `runtime_smoke.rb` manual checklist** (SMB vs Icon Panel stuck-open) against
  the snapshot.
- **Stop counting Bucket A as runtime coverage.** Keep the `RuntimeGuard*` files as hygiene
  tripwires, but every behavior claim must map to a Bucket C `layout snapshot` assertion.

---

## 5. Remediation tracking

This doc is the program tracker. As each blind family gets a real runtime gate, update its
row in §3/§4 and link the probe + the issue it now reproduces. A family is **closed** only
when its gate fails on the real bug at runtime and passes on the fix (fail-before /
pass-after), and is default-on in the release path. Source-fingerprint guards never close a
row — see the NO BLIND TESTS rule (DEVELOPMENT.md § Testing).

---

## 6. Changelog of de-blinded gates

### 2026-06-24 — FM-1 was itself a blind gate; now a real zone-delta behavioral gate

The FM-1 hidden-outbound gate
(`Scripts/lib/live_zone_smoke_hidden_outbound_gate.rb`) originally asserted
`alwaysHiddenSeparatorLiveFrameReadable == true` reached from a genuinely-hidden
length-10000 state, as a "root-cause guard" that was supposed to fail even before a
move. A runtime diagnosis proved that assertion **UNSATISFIABLE by correct product
design**: the outbound-move path gates on `sourceFrameIsOnScreen(request)` — the moved
icon's own AX frame after `showAll()` — **not** on
`currentLiveAlwaysHiddenSeparatorFrame()`. At length 10000 the AH separator window is
legitimately off-screen, so its live frame is never readable from the hidden resting
state, yet the real move (`move icon to visible "<unique_id>"`) succeeds and sticks.
The gate therefore **fails-closed forever** regardless of whether the move works — the
exact blind-proxy anti-pattern this audit forbids (it asserted a proxy that cannot
track real behavior).

Fix: the gate's PRIMARY assertion is now the **real zone delta** — stage the SBF
fixture into Always Hidden, drive the separator to genuine-hidden (length ~10000,
asserted via `alwaysHiddenSeparatorLength`), issue the real product move via
`move_and_verify(..., staged_always_hidden_outbound: true)`, then assert the fixture
**LEFT** `alwaysHidden` (`assert_left_always_hidden_zone_delta!`) and **STAYED**
(`assert_zone_stays_stable_after_move`). It fails iff the move no-ops (#155/#156/#166)
or the icon snaps back. `alwaysHiddenSeparatorLiveFrameReadable` is retained only as an
**advisory breadcrumb**, read solely in the contracted (length ≤ 14) post-`showAll()`
window — never asserted from length 10000, never the release bar. The misleading
"separator may still sit live in the band at length 10000" comment in
`LayoutSnapshotCommand.swift` and the unreachable-precondition example in
the testing rules were corrected. The gate is default-on + release-blocking via
`project_qa_runtime_preflight` (opt-out `SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1`).
