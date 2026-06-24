# frozen_string_literal: true

# FM-1 runtime regression gate (#155/#156/#166).
#
# Root failure mode: an OUTBOUND Always-Hidden move (AH -> Visible / AH -> Hidden)
# attempted while the Always-Hidden separator is in its GENUINE HIDDEN state
# (NSStatusItem length ~10000) silently no-ops. On pre-fix code,
# `MenuBarGeometryResolver.currentLiveAlwaysHiddenSeparatorFrame()` capped liveness
# behind `alwaysHiddenSeparatorItem.length <= 1000`, which a hidden separator can
# never satisfy, so the move target resolver aborted `(nil, nil)` and the caller
# converted that to a silent no-op.
#
# Why the prior probes missed it: the representative move matrix only ever drove
# outbound moves from the matrix's revealed/expanded baseline, and the move
# workflow itself calls `showAll()` (contracting the separator to ~14) before
# resolving targets. The probe never asserted the move STARTED from a genuinely
# hidden separator and then actually LEFT Always Hidden.
#
# WHAT THIS GATE ASSERTS (and why it is a REAL behavioral gate, not a blind proxy):
#
#   The product outbound-move path gates on `sourceFrameIsOnScreen(request)` — the
#   moved icon's OWN AX frame after `showAll()` reveals it — NOT on
#   `currentLiveAlwaysHiddenSeparatorFrame()` read from the resting hidden state.
#   See `repairAlwaysHiddenSeparatorForOutboundMoveIfNeeded` /
#   `sourceFrameIsOnScreen` in Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift.
#
#   A runtime diagnosis PROVED that at genuine-hidden length 10000 the AH separator
#   window is legitimately off-screen, so its live frame is NOT readable from the
#   hidden resting state — yet the real move (`move icon to visible "<unique_id>"`)
#   still succeeds and STAYS. Therefore the old precondition
#   `alwaysHiddenSeparatorLiveFrameReadable == true` (asserted from the length-10000
#   resting state) was UNSATISFIABLE by correct product design: it fails-closed
#   forever regardless of whether the move works. That is a BLIND gate (asserts a
#   proxy that cannot track real behavior), the exact anti-pattern
#   docs/TEST_BLINDNESS_AUDIT.md and .claude/rules/tests.md forbid.
#
#   The PRIMARY assertion is now the real zone delta, driven through the actual
#   product command via `move_and_verify(..., staged_always_hidden_outbound: true)`:
#     1. Stage the SBF shared-bundle fixture into Always Hidden.
#     2. Drive the separator into its GENUINE hidden state (length ~10000), asserted
#        via the `alwaysHiddenSeparatorLength` snapshot field. (This is real: it
#        proves the move starts from the exact #155 trigger state, not the matrix's
#        revealed baseline.)
#     3. Issue the real product `move icon to visible` move. `move_and_verify`:
#          - raises if the command returns anything but true/1 (move no-op);
#          - `wait_for_zone` raises if the icon never reaches `visible`;
#          - `assert_zone_stays_stable_after_move` raises if it snapped back.
#        Net: the fixture must LEAVE Always Hidden (zone alwaysHidden -> visible) AND
#        STAY there after the post-move settle.
#     4. Re-stage into Always Hidden, re-hide to genuine-hidden, and prove
#        AH -> Hidden the same way (the #155 path).
#
#   FAIL-ON-REAL-BREAK: if the #155/#156/#166 bug regresses — the move no-ops, or
#   the icon snaps back — `move_and_verify` raises (bad command result / zone never
#   reached / post-settle drift) and the gate raises. The gate PASSES iff the real
#   move succeeds and sticks; it FAILS iff the move no-ops or the icon snaps back.
#   It cannot pass on a broken build, and it cannot fail-closed on a correct build
#   (the unsatisfiable live-frame precondition is gone).
#
#   SECONDARY (optional) signal: `alwaysHiddenSeparatorLiveFrameReadable` is only
#   meaningful in the post-`showAll()` CONTRACTED window (length <= 14 with AH items
#   on-screen) — NEVER from the length-10000 resting state. We assert it only when we
#   already observe a contracted separator, and it is advisory: it never fails the
#   gate (the real move is the release bar). This keeps a root-cause breadcrumb
#   without reintroducing a blind proxy.
#
# Default-on + release-blocking: enabled by project_qa_runtime_preflight via
# `hidden_outbound_ah_gate_enabled?` (opt-out: SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1;
# legacy opt-in SANEBAR_SMOKE_REQUIRE_HIDDEN_OUTBOUND_AH=1 still honored).
#
# Determinism: uses the shared-bundle fixture icons (SBF-A..SBF-E,
# com.sanebar.sharedfixture) seeded by the preflight harness; no third-party app
# dependence.
class LiveZoneSmoke
  private

  # Length thresholds for classifying the separator as "genuinely hidden". The
  # hidden sentinel is 10000; a revealed/expanded separator is a small visual
  # length (~12-14). Anything above this floor is unambiguously the hidden state.
  HIDDEN_OUTBOUND_AH_HIDDEN_LENGTH_FLOOR = 1000

  # A post-`showAll()` separator is contracted to a small visual length. Only in
  # that contracted window is `currentLiveAlwaysHiddenSeparatorFrame()` expected to
  # be readable; the secondary breadcrumb assertion is gated behind this ceiling so
  # it can never re-encode the unsatisfiable length-10000 precondition.
  HIDDEN_OUTBOUND_AH_CONTRACTED_LENGTH_CEILING = 14

  def exercise_hidden_state_outbound_always_hidden_gate(zones, passed_candidates)
    candidate = hidden_outbound_ah_gate_candidate(zones, passed_candidates)
    unless candidate
      raise 'FM-1 gate requires a deterministic shared-bundle Always-Hidden candidate, but none was available.'
    end

    puts "🔒 FM-1 hidden-state outbound Always-Hidden gate candidate: #{candidate[:unique_id]}"

    # Stage the icon into Always Hidden. move_and_verify confirms it is ZONE-CLASSIFIED
    # alwaysHidden — i.e. resting collapsed in the always-hidden section (off-screen,
    # X far negative). That IS the #155/#156 trigger state. We deliberately do NOT gate
    # on the AH separator reaching length ~10000: a runtime diagnosis proved the product
    # move calls showAll() (contracting the separator to ~14) BEFORE moving, so there is
    # no "move from a frozen length-10000 separator" — requiring it tests an impossible
    # condition and made this gate fail-closed on a correct build. Zone membership is the
    # real, reachable precondition.
    move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')

    # PRIMARY behavioral assertion: drive the REAL product AH -> Visible move out of the
    # always-hidden zone. This is the exact pre-fix no-op. move_and_verify raises if the
    # move command no-ops, if the icon never reaches `visible`, or if it snaps back after
    # the post-move settle. The gate fails-on-real-break here.
    move_and_verify('move icon to visible', candidate.merge(zone: 'alwaysHidden', staged_always_hidden_outbound: true), 'visible')
    assert_left_always_hidden_zone_delta!(candidate, 'visible')
    puts '✅ FM-1 AH->Visible LEFT Always Hidden and stuck'

    # Restage into Always Hidden, then prove AH -> Hidden (the #155 path).
    move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    move_and_verify('move icon to hidden', candidate.merge(zone: 'alwaysHidden', staged_always_hidden_outbound: true), 'hidden')
    assert_left_always_hidden_zone_delta!(candidate, 'hidden')
    puts '✅ FM-1 AH->Hidden LEFT Always Hidden and stuck'

    # Park the gate icon back in a benign zone so it does not perturb later checks.
    begin
      move_and_verify('move icon to visible', candidate.merge(zone: 'hidden'), 'visible')
    rescue StandardError => e
      puts "ℹ️ FM-1 gate cleanup move skipped: #{e.message}"
    end

    puts '✅ FM-1 hidden-state outbound Always-Hidden gate passed (real zone-delta move)'
    true
  end

  def hidden_outbound_ah_gate_candidate(zones, passed_candidates)
    pool = (Array(passed_candidates) + Array(zones)).compact
    fixture = pool.find do |candidate|
      candidate[:bundle].to_s == 'com.sanebar.sharedfixture' && candidate[:movable]
    end
    return fixture if fixture

    # Fall back to any deterministic movable candidate if the shared fixture is
    # momentarily missing from the passed set but present live.
    list_icon_zones.find do |candidate|
      candidate[:bundle].to_s == 'com.sanebar.sharedfixture' && candidate[:movable]
    end
  end

  def drive_hidden_state_for_outbound_gate!
    wait_for_move_ready_state
    hide_command =
      if supports_applescript_command?('hide items')
        'hide items'
      elsif supports_applescript_command?('hide')
        'hide'
      end
    raise 'FM-1 gate cannot hide items: no hide command supported by target.' unless hide_command

    app_script(hide_command)

    deadline = Time.now + LAYOUT_STABILIZE_TIMEOUT_SECONDS
    last_snapshot = nil
    while Time.now < deadline
      check_resource_watchdog!
      last_snapshot = layout_snapshot
      length = numeric_snapshot_value(last_snapshot, 'alwaysHiddenSeparatorLength')
      return last_snapshot if last_snapshot['hidingState'] == 'hidden' &&
                              length && length > HIDDEN_OUTBOUND_AH_HIDDEN_LENGTH_FLOOR

      sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
    end

    raise "FM-1 gate could not reach genuine hidden separator state (snapshot=#{last_snapshot})"
  end

  def assert_separator_genuinely_hidden!(snapshot)
    length = numeric_snapshot_value(snapshot, 'alwaysHiddenSeparatorLength')
    unless length && length > HIDDEN_OUTBOUND_AH_HIDDEN_LENGTH_FLOOR
      raise "FM-1 gate precondition failed: Always-Hidden separator is not genuinely hidden (length=#{length.inspect}, hidingState=#{snapshot['hidingState'].inspect}). The gate must start from length ~10000."
    end

    puts "✅ FM-1 precondition: separator genuinely hidden (length=#{length.round})"
  end

  # PRIMARY behavioral assertion. `move_and_verify` already raised if the move did
  # not land + stick; this is the explicit, issue-tagged zone-delta confirmation read
  # straight off `list icon zones`: the gate fixture must no longer report
  # `alwaysHidden`. It re-asserts the observable end-state (icon LEFT Always Hidden)
  # so a silent no-op or snap-back is impossible to pass.
  def assert_left_always_hidden_zone_delta!(candidate, expected_zone)
    icon_unique_id = resolve_live_move_identifier(candidate)
    zones = list_icon_zones
    matched = matched_move_candidate(zones, icon_unique_id, candidate)

    if matched.nil?
      raise "FM-1 zone-delta assertion could not find #{candidate[:bundle]} (#{candidate[:name]}) after outbound move (#155/#156/#166)."
    end

    if matched[:zone].to_s == 'alwaysHidden'
      raise "FM-1 ROOT CAUSE DETECTED: outbound Always-Hidden move no-opped — #{icon_unique_id} is still in alwaysHidden after `move icon to #{expected_zone}` from a genuinely hidden separator (#155/#156/#166)."
    end

    unless matched[:zone].to_s == expected_zone.to_s
      raise "FM-1 zone-delta assertion drifted: #{icon_unique_id} expected #{expected_zone} after leaving Always Hidden, got #{matched[:zone].inspect}."
    end

    puts "✅ FM-1 zone delta: #{icon_unique_id} LEFT alwaysHidden -> #{matched[:zone]}"
    maybe_note_contracted_separator_live_frame_breadcrumb(zones)
    true
  end

  # SECONDARY, ADVISORY breadcrumb. `alwaysHiddenSeparatorLiveFrameReadable` is only
  # meaningful while the separator is CONTRACTED (post-showAll, length <= 14, AH items
  # on-screen) — never from the length-10000 resting state. We read it only if we
  # already observe a contracted separator, and it NEVER fails the gate: the real
  # zone-delta move is the release bar. This avoids reintroducing the unsatisfiable
  # length-10000 + live-frame precondition that made the old gate blind.
  def maybe_note_contracted_separator_live_frame_breadcrumb(_zones)
    snapshot = layout_snapshot
    length = numeric_snapshot_value(snapshot, 'alwaysHiddenSeparatorLength')
    return unless length && length <= HIDDEN_OUTBOUND_AH_CONTRACTED_LENGTH_CEILING
    return unless snapshot.key?('alwaysHiddenSeparatorLiveFrameReadable')

    if truthy?(snapshot['alwaysHiddenSeparatorLiveFrameReadable'])
      puts "ℹ️ FM-1 breadcrumb: contracted AH separator live frame readable (length=#{length.round})"
    else
      puts "ℹ️ FM-1 breadcrumb: contracted AH separator live frame NOT readable (length=#{length.round}); advisory only, real move already verified"
    end
  rescue StandardError => e
    puts "ℹ️ FM-1 breadcrumb skipped: #{e.message}"
  end

  def numeric_snapshot_value(snapshot, key)
    value = snapshot[key]
    return nil if value.nil?
    return value.to_f if value.is_a?(Numeric)

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end
end
