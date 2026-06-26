#!/bin/bash
# air_ir_test.sh — foolproof setup + helpers for SaneBar IN-REAL-LIFE menu-bar
# testing on the notched MacBook Air. The notch/off-screen-separator code paths
# only reproduce on a built-in notched display, so move/reveal/recovery bugs
# MUST be verified here, with real mouse input (computer-use), not AppleScript
# (AppleScript move takes a different code path and hides the real behavior).
#
# This script does the deterministic setup so a fresh session never re-learns
# the build/sign/bypass/log dance. The MOUSE interaction is still agent-driven
# (computer-use) — `setup` prints the exact coordinates + the atomic-batch
# recipe + the zone-move matrix the agent should follow.
#
# Usage:
#   Scripts/air_ir_test.sh setup      # build+sign+deploy, enable local-UI, start logs, print recipe
#   Scripts/air_ir_test.sh zones      # ground-truth: every icon's real zone (read-only)
#   Scripts/air_ir_test.sh logs       # tail the live debug log, move-relevant lines only
#   Scripts/air_ir_test.sh moves      # show just the move/zone events from the log
#   Scripts/air_ir_test.sh teardown   # stop logs, remove the local-UI bypass (re-enable hooks)
#
# Hard-won lessons baked in (2026-06-26 session) — DO NOT re-learn these:
#   • Build/sign/deploy: `sane_test.rb SaneBar --local` builds ProdDebug, stages
#     to /Applications, AND re-signs with the Developer ID so the existing
#     Accessibility/TCC grant still applies (step "Re-sign with Developer ID").
#     No manual codesign/toggle needed anymore.
#   • computer-use on the Air is gated by the Mini-first guard. The sanctioned
#     opt-in is the project bypass file `.claude/bypass_active.json` (this script
#     creates it). It disables ALL sanetools blocks — `teardown` removes it.
#   • The agent must `request_access` for BOTH "SaneBar" and "Finder" (menu-bar/
#     desktop clicks count as desktop interaction → need the Finder grant).
#   • `--level debug` log streaming WORKS here (the old runbook claim that only
#     --level info works is wrong for live `log stream`). We use debug.
#   • The Icon Panel is HIGHLY transient + ⇧⌘Space TOGGLES it. See setup output
#     for the only reliable open/interact pattern.

set -u
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_PATH="/tmp/sanebar_ir.log"
INFRA="${SANEAPPS_INFRA:-$HOME/SaneApps/infra/SaneProcess}"
SUBSYS='subsystem == "com.sanebar.app"'

print_recipe() {
  cat <<'RECIPE'
──────────────────────────────────────────────────────────────────────────────
 AGENT RECIPE (computer-use) — follow exactly; the panel is transient.
──────────────────────────────────────────────────────────────────────────────
 0. request_access for ["SaneBar","Finder"]. If Claude/Terminal is frontmost,
    `open_application Finder` first (key/click need a GRANTED app frontmost).

 1. The Icon Panel auto-dismisses between tool calls AND ⇧⌘Space toggles it, so
    do an ENTIRE interaction in ONE computer_batch. Reliable open-from-unknown:
       left_click (505,65)   # the panel's red close btn IF open; harmless if not
       wait 0.4
       key shift+cmd+space   # now opens fresh
    (clicking empty desktop does NOT dismiss the panel — it's a floating panel.)

 2. Panel coordinates (stable, panel opens centred):
       All tab .............. (749,104)   Hidden (533,104) Visible (595,104) AlwaysHidden (677,104)
       Filter box ........... (685,174)
       First/only tile ...... (541,251)   ← filter to ONE icon so it's here
       red close button ..... (505,65)

 3. Verify CLASSIFICATION (right-click menu must match the real zone):
       batch: [click(505,65), wait .4, key shift+cmd+space, wait 1.3,
               click All(749,104), click filter(685,174), type "<iconname>",
               wait .8, right_click(541,251), wait .6, zoom(545,250,705,430)]
    Correct menus:  Visible→{Move to Hidden, Move to Always Hidden}
                    Hidden →{Move to Visible, Move to Always Hidden}
                    AlwaysHidden→{Move to Visible, Move to Hidden}
    (the option that would move it to where it ALREADY is must be absent.)

 4. MOVE via menu: append `left_click(<menu item>)` to the batch. Menu item Y:
       1st move row ~y381, 2nd move row ~y414 (x ~600-622). Read the zoom first.
 5. MOVE via drag (human-style): in the filtered All view,
       left_click_drag start (541,251) → Hidden(533,104)/Visible(595,104)/AlwaysHidden(677,104)
 6. After EVERY move, verify ground truth (separate Bash, not computer-use):
       Scripts/air_ir_test.sh zones | grep -i <iconname>
    The zone must actually change. "Move complete - direct hide" in the log is
    NOT proof — it logs even on the abort path. Trust `zones` + a real drag delta.

 7. Full matrix to cover: H→V, V→AH, AH→H (menu) and V→H, H→AH, AH→V (drag).
──────────────────────────────────────────────────────────────────────────────
RECIPE
}

case "${1:-}" in
  setup)
    echo "▶ Building + signing + deploying ProdDebug to /Applications (Air, --local)…"
    ruby "$INFRA/scripts/sane_test.rb" SaneBar --local --no-logs || { echo "❌ build failed"; exit 1; }
    echo "▶ Enabling local-UI (sanctioned bypass for computer-use on the Air)…"
    touch "$PROJECT_DIR/.claude/bypass_active.json"
    echo "▶ Starting live debug log → $LOG_PATH"
    pkill -f "log stream --level debug --predicate.*com.sanebar.app" 2>/dev/null
    : > "$LOG_PATH"
    nohup log stream --level debug --predicate "$SUBSYS" --style compact > "$LOG_PATH" 2>&1 &
    echo "   log stream PID: $!"
    echo "▶ Running app:"; pgrep -lx SaneBar || echo "   (not detected — check /Applications/SaneBar.app)"
    print_recipe
    echo "When done:  Scripts/air_ir_test.sh teardown"
    ;;
  zones)
    osascript -e 'tell application "SaneBar" to list icon zones' 2>&1 | tr ',' '\n' | awk 'NF'
    ;;
  logs)
    tail -60 "$LOG_PATH" 2>/dev/null | grep -iE "MOVE ICON START|toHidden=|task started|moveMenuBarIcon|Icon frame AFTER|Move complete|recreating status items|Recovered live|Cannot get separator|classifyItems|Accepting cached" | grep -viE "window.frame|getMainStatusItem"
    ;;
  moves)
    grep -nE "MOVE ICON START|toHidden=|moveMenuBarIcon|targetLane|Move complete|recreating status items|Cannot get separator|classifyItems: visible" "$LOG_PATH" 2>/dev/null | grep -viE "window.frame|getMainStatusItem" | tail -40
    ;;
  teardown)
    echo "▶ Stopping log stream…"; pkill -f "log stream --level debug --predicate.*com.sanebar.app" 2>/dev/null
    echo "▶ Removing local-UI bypass (re-enabling hooks)…"
    trash "$PROJECT_DIR/.claude/bypass_active.json" 2>/dev/null || rm -f "$PROJECT_DIR/.claude/bypass_active.json"
    echo "✅ Done. Single instance:"; pgrep -lx SaneBar
    echo "   (Restore the notarized release build via the release pipeline when finished testing.)"
    ;;
  *)
    echo "usage: Scripts/air_ir_test.sh {setup|zones|logs|moves|teardown}"; exit 1
    ;;
esac
