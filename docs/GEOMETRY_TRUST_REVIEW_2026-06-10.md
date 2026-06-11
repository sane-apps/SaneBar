# Menu Bar Geometry Trust Review — 2026-06-10

First-principles review of SaneBar's recurring layout/recovery issue families
(GitHub #86–#155), run before the 2.1.67 release. This file is the durable
record of the findings, evidence, and the architecture decisions that came out
of it. Read this before "fixing" any new arrangement/recovery report — most
new reports belong to a family documented here.

## Verdict

The architecture (separator-length hiding, exact-ID Cmd+drag moves, position
persistence, validation/recovery ladders) is the right track. There is no API
to control other apps' status items; every competitor uses the same toolkit
and has the same open bug families. The chronic pain came from two specific
defects, not the design:

1. The geometry layer could lie about how much it knew (stale/estimated
   coordinates gaining trust), and
2. The recovery layer acted confidently — and destructively — on those lies.

## Evidence that this is platform-hard, not SaneBar-specific

- Ice (open source, jordanbaird/Ice) has the identical families open:
  - #496 arrangement not sticking
  - #344 items move to hidden/always-hidden on their own
  - #675 always-hidden icons disappeared
  - #773 all icons land in the hidden section
- BetterDisplay #5314: macOS 26.4.1 flips NSStatusItem visibility every
  ~200ms (NSStatusItemChangeVisibilityAction loop); the icon never appears.
  This is the #152 signature. The OS does this; the app cannot win by
  recreating items.
- Apple Feedback FB9052637: toggling NSStatusItem.isVisible destroys the
  saved position. FB8732253: macOS stopped preserving menu bar order.
- Hidden Bar (simpler: no exact-ID replay, no recovery) has far fewer
  arrangement complaints — and far fewer features. Aggressiveness of
  intervention correlates directly with this bug class.

## Root causes found (and fixed in 67227a4)

1. Estimate laundering: MenuBarGeometryResolver wrote estimate-derived values
   into MenuBarGeometryCache; later reads reported them as "cached" (trusted).
   Separator was estimated from main AND main from separator — circular
   bootstrapping of garbage under double staleness.
2. No configuration binding: cached coordinates survived display-arrangement
   changes (and were deliberately preserved while hidden), so recovery
   consumed coordinates from a different monitor setup. This was the #136
   frozen-drift signature (separator=1576/main=1612/gap=948 forever).
3. Sign-based liveness: frameLooksLive required originX > 0. Displays
   arranged LEFT of the primary have negative global X → permanently "stale"
   → cache/estimate-only operation → recovery loops. Conversely, offscreen
   parked windows (y=-22, #152) passed when X was positive.
4. Absolute drift zone: mainRightGap > min(480, max(300, w*0.18)) triggered
   auto-recovery. Users who legitimately keep icons right of the toggle were
   perpetually "drifted" — recovery destroyed intentional layouts.
5. Unconditional replay: wake replays fired synthetic Cmd+drags on stale
   geometry with no consent, no rate limit, no announcement → cursor hijack
   reports (#151, #154) — users suspected malware.
6. Recovery dead-end (fixed earlier in 0bb04f4): the 2.1.64 suppression gates
   returned .stop with zero attempts AND made Health > Repair a no-op (#152).

## Architecture rules going forward

- Geometry values carry provenance. Only live observations enter the cache;
  entries are bound to a display-configuration fingerprint and expire with it
  (MenuBarDisplayConfiguration.currentFingerprint, injectable for tests).
- Liveness is screen-relative: a window is live iff it sits in its OWN
  screen's menu bar band (statusItemFrameLooksLive(frame:screenFrame:)).
  Never sign checks. Scalar variants remain only for diagnostics paths.
- No automatic synthetic input without consent: every Cmd+drag passes
  MenuBarAutomaticMoveGate. User origins always pass; .systemWakeRecovery
  requires the gate armed (only done with live-confidence geometry) and is
  rate-limited (6/min). Replays otherwise downgrade to audit-only.
- Soft drift is judged against SaneBar's own persisted preferred position
  (distance-from-right, 160pt tolerance), not an absolute zone. Hard
  invariant (separatorX >= mainX) still auto-recovers. macOS rewrites the
  persisted value when the user drags the toggle, so intent tracks the user.
- When the OS flaps item health (>=4 transitions in 10s across validation
  polls), recovery goes dormant for 5 minutes and surfaces the
  System Settings > Menu Bar hint (MenuBarVisibilityFlapDetector). Manual
  repair bypasses and clears dormancy. Never fight the OS visibility loop.
- Suppression suspicion gets ONE automatic repair attempt, then stops; an
  explicit user Repair always attempts.

## Release-gauntlet addendum (2026-06-11, shipped in 2.1.67)

The 2.1.67 release gates surfaced three runtime defects the unit suite
could not see, now fixed and encoded in tests:

- Visible-lane drag targets hugged the pre-drag separator edge; menu bar
  reflow during insertion stranded icons just left of the post-reflow
  separator, and honest live-boundary verification (correctly) refused
  them. Targets now aim at the visible-lane midpoint, clamped inside the
  lane (the #93 overshoot protection holds). This was also the customer
  "cannot move icon to visible" class (#138, #156).
- Replay-mode final calibration: startup/relaunch reconciliation may
  physically restore standing intent (hide-all-other allow-list, pins)
  when geometry confidence is live OR cached — cached is trustworthy by
  construction post-provenance. Passive wake replays are ALWAYS
  audit-only: the wake probe enforces a zero-cursor-movement contract
  (#151/#154), and violations surface via the deferred-repair path.
- The runtime smoke now neutralizes standing-intent settings for its
  window (restored after); otherwise startup reconciliation physically
  fights the QA seeder ("zone setup drifted after settle").

## Known remaining gaps (not yet done)

- Three recreate paths still exist (recreateItemsFromPersistedPositions,
  recreateItemsWithBumpedVersion, resetPersistentStatusItemState) plus the
  per-screen-width display-backup system. They should collapse into one
  invariant-based "rebuild at safe anchors" primitive. The invariants
  (separator left of main, main near persisted intent, preserve lane width)
  fully determine placement; the pixel-backup archaeology adds failure
  surface without information.
- Deferred-replay UX: when the consent gate blocks an automatic replay there
  is a log line but no "Restore my layout?" one-click prompt. Replay re-runs
  after the next healthy validation, which covers most cases.
- The drift-vs-intent tolerance (160pt) and flap thresholds (4 in 10s, 5min
  dormancy) are first guesses; revisit against telemetry in issue reports.
- SaneProcess verify banner can lie: SaneMaster printed "Tests passed!" over
  a real Swift Testing failure (and over a 600s timeout). verify.rb is past
  the 800-line hook split limit; split it, then make the banner reflect the
  Swift Testing result line ("Test run with N tests ... failed") and the
  xcodebuild exit code. Until then, trust test_output.txt, not the banner.
- R4 settings-vocabulary issues (#144, #145): "layout stability", "extra
  dividers" wording still confuses users; not addressed in this pass.

## Issue-family map (for triaging new reports)

- R1 move-classification (#93, #94, #95, #106, #117, #129, #138, #140, #155):
  moves fail/misfire — first check anchor sources and liveness in diagnostics.
- R2 browse-rehide (#101, #105, #116, #143, #146): reveal/rehide interaction.
- R3 persistence-reset (#92, #115, #121, #123, #124, #125, #128, #129, #135,
  #136, #139, #142, #147, #150, #153): arrangement lost after wake/display
  change/update — check provenance expiry and replay gating first.
- Icon disappearance (#86, #91, #107, #108, #126, #130, #133, #152): check
  for the OS visibility flap (dormancy log line) and System Settings
  suppression before touching recovery code.
- Cursor hijack (#151, #154): should be extinct; any new report means a move
  bypassed MenuBarAutomaticMoveGate — find the entry point, don't relax the gate.
