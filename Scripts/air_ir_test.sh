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
#   scripts/air_ir_test.sh setup                 # build+sign+deploy, enable local-UI, start logs, print recipe
#   scripts/air_ir_test.sh start <case> <SBF-X>  # capture before zone+screenshot for one real-input move
#   scripts/air_ir_test.sh finish <case>         # capture after zone+screenshot, append receipt case
#   scripts/air_ir_test.sh validate              # require all 6 real-input move cases in the receipt
#   scripts/air_ir_test.sh zones                 # ground-truth: every icon's real zone (read-only)
#   scripts/air_ir_test.sh logs                  # tail the live debug log, move-relevant lines only
#   scripts/air_ir_test.sh moves                 # show just the move/zone events from the log
#   scripts/air_ir_test.sh teardown              # stop logs, remove the local-UI bypass (re-enable hooks)
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
AIR_ROOT="$PROJECT_DIR/outputs/runtime-preflight/air-ir"
AIR_RECEIPT="$PROJECT_DIR/outputs/runtime-preflight/sanebar_air_ir_move_receipt.json"
AIR_STATE="/tmp/sanebar_air_ir_run_dir"

canonical_case_id() {
  case "$1" in
    menu-hidden-visible) echo "menu-hidden-visible" ;;
    menu-visible-alwaysHidden|menu-visible-always-hidden) echo "menu-visible-alwaysHidden" ;;
    menu-alwaysHidden-hidden|menu-always-hidden-hidden) echo "menu-alwaysHidden-hidden" ;;
    drag-visible-hidden) echo "drag-visible-hidden" ;;
    drag-hidden-alwaysHidden|drag-hidden-always-hidden) echo "drag-hidden-alwaysHidden" ;;
    drag-alwaysHidden-visible|drag-always-hidden-visible) echo "drag-alwaysHidden-visible" ;;
    *) return 1 ;;
  esac
}

case_spec() {
  case "$1" in
    menu-hidden-visible) echo "menu hidden visible" ;;
    menu-visible-alwaysHidden) echo "menu visible alwaysHidden" ;;
    menu-alwaysHidden-hidden) echo "menu alwaysHidden hidden" ;;
    drag-visible-hidden) echo "drag visible hidden" ;;
    drag-hidden-alwaysHidden) echo "drag hidden alwaysHidden" ;;
    drag-alwaysHidden-visible) echo "drag alwaysHidden visible" ;;
    *) return 1 ;;
  esac
}

normalize_zone() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
  case "$raw" in
    visible) echo "visible" ;;
    hidden) echo "hidden" ;;
    alwayshidden) echo "alwaysHidden" ;;
    *) echo "$1" ;;
  esac
}

ensure_air_run_dir() {
  if [ -f "$AIR_STATE" ]; then
    local existing
    existing="$(cat "$AIR_STATE" 2>/dev/null || true)"
    if [ -n "$existing" ]; then
      mkdir -p "$existing"
      echo "$existing"
      return 0
    fi
  fi
  mkdir -p "$AIR_ROOT"
  local run_dir
  run_dir="$AIR_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$run_dir"
  printf '%s\n' "$run_dir" > "$AIR_STATE"
  echo "$run_dir"
}

new_air_run_dir() {
  mkdir -p "$AIR_ROOT"
  local run_dir
  run_dir="$AIR_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$run_dir"
  printf '%s\n' "$run_dir" > "$AIR_STATE"
  echo "$run_dir"
}

capture_zones() {
  osascript -e 'tell application "SaneBar" to list icon zones' 2>&1 | tr ',' '\n' | awk 'NF'
}

zone_for_fixture() {
  local zones_file="$1"
  local fixture="$2"
  awk -F '\t' -v fixture="$fixture" '
    BEGIN { needle = tolower(fixture) }
    {
      id = tolower($4)
      name = tolower($5)
      if (index(id, needle) || index(name, needle)) {
        print $1
        exit
      }
    }
  ' "$zones_file"
}

write_air_receipt() {
  local run_dir="$1"
  ruby -rjson -rtime -rfileutils - "$PROJECT_DIR" "$run_dir" "$AIR_RECEIPT" <<'RUBY'
project_dir, run_dir, receipt_path = ARGV
required = {
  'menu-hidden-visible' => ['menu', 'hidden', 'visible'],
  'menu-visible-alwaysHidden' => ['menu', 'visible', 'alwaysHidden'],
  'menu-alwaysHidden-hidden' => ['menu', 'alwaysHidden', 'hidden'],
  'drag-visible-hidden' => ['drag', 'visible', 'hidden'],
  'drag-hidden-alwaysHidden' => ['drag', 'hidden', 'alwaysHidden'],
  'drag-alwaysHidden-visible' => ['drag', 'alwaysHidden', 'visible']
}

def capture(*argv)
  IO.popen(argv, &:read).to_s.strip
rescue StandardError
  ''
end

def display_summary
  raw = capture('system_profiler', 'SPDisplaysDataType', '-json')
  payload = JSON.parse(raw)
  displays = Array(payload['SPDisplaysDataType']).flat_map { |gpu| Array(gpu['spdisplays_ndrvs']) }
  names = displays.map { |display| display['_name'].to_s }.reject(&:empty?)
  built_in = displays.any? do |display|
    [display['_name'], display['spdisplays_display_type'], display['spdisplays_connection_type']]
      .compact.join(' ').match?(/built.?in|internal|retina/i)
  end
  main = displays.any? { |display| display['spdisplays_main'].to_s == 'spdisplays_yes' }
  { 'built_in' => built_in, 'main' => main, 'names' => names }
rescue StandardError
  { 'built_in' => false, 'main' => false, 'names' => [] }
end

cases = Dir.glob(File.join(run_dir, '*.case.json')).sort.map { |path| JSON.parse(File.read(path)) }
cases_by_id = cases.each_with_object({}) { |item, memo| memo[item['id'].to_s] = item }
missing = required.keys - cases_by_id.keys
invalid = required.filter_map do |id, spec|
  item = cases_by_id[id]
  next if item.nil?
  next if item['action'].to_s == spec[0] &&
          item['before_zone'].to_s == spec[1] &&
          item['after_zone'].to_s == spec[2] &&
          item['before_zone'].to_s != item['after_zone'].to_s &&
          item['fixture_id'].to_s.match?(/SBF-[A-E]/) &&
          !item['input_path'].to_s.match?(/applescript|runScriptMove|move icon to/i) &&
          !Array(item['log_excerpt']).join("\n").strip.empty? &&
          File.file?(item['before_screenshot'].to_s) &&
          File.file?(item['after_screenshot'].to_s) &&
          File.file?(item['before_zones_path'].to_s) &&
          File.file?(item['after_zones_path'].to_s) &&
          File.file?(item['log_path'].to_s)

  id
end

info_plist = '/Applications/SaneBar.app/Contents/Info.plist'
candidate = {
  'app_path' => '/Applications/SaneBar.app',
  'app_version' => capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleShortVersionString', info_plist),
  'app_build' => capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleVersion', info_plist),
  'process_path' => '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
}
status = missing.empty? && invalid.empty? ? 'passed' : 'incomplete'
receipt = {
  'app' => 'SaneBar',
  'status' => status,
  'proof' => 'air_ir_move_matrix',
  'generated_at' => Time.now.utc.iso8601,
  'launch_method' => 'ruby ~/SaneApps/infra/SaneProcess/scripts/sane_test.rb SaneBar --local --no-logs',
  'git_sha' => capture('git', '-C', project_dir, 'rev-parse', 'HEAD'),
  'host' => capture('hostname'),
  'display' => display_summary,
  'ingress' => %w[sane_test hotkey click right_click_menu drag_tile],
  'candidate' => candidate,
  'run_dir' => run_dir,
  'missing_cases' => missing,
  'invalid_cases' => invalid,
  'cases' => cases
}
FileUtils.mkdir_p(File.dirname(receipt_path))
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
puts "receipt=#{receipt_path} status=#{status} cases=#{cases.length}/#{required.length}"
RUBY
}

start_case() {
  local raw_case_id="${1:-}"
  local fixture="${2:-}"
  local case_id
  case_id="$(canonical_case_id "$raw_case_id")" || { echo "❌ unknown case: $raw_case_id"; exit 1; }
  [ -n "$fixture" ] || { echo "usage: scripts/air_ir_test.sh start <case> <SBF-X>"; exit 1; }
  local spec action expected_before expected_after
  spec="$(case_spec "$case_id")"
  set -- $spec
  action="$1"
  expected_before="$2"
  expected_after="$3"
  local run_dir case_dir before_zones before_screenshot pending actual_zone
  run_dir="$(ensure_air_run_dir)"
  case_dir="$run_dir/$case_id"
  mkdir -p "$case_dir"
  before_zones="$case_dir/before-zones.txt"
  before_screenshot="$case_dir/before.png"
  pending="$run_dir/$case_id.pending.json"
  capture_zones > "$before_zones"
  actual_zone="$(normalize_zone "$(zone_for_fixture "$before_zones" "$fixture")")"
  if [ "$actual_zone" != "$expected_before" ]; then
    echo "❌ $fixture expected in $expected_before before $case_id, got ${actual_zone:-missing}"
    echo "   Check: scripts/air_ir_test.sh zones | grep -i '$fixture'"
    exit 1
  fi
  screencapture -x "$before_screenshot"
  ruby -rjson -rtime -e 'path, id, action, fixture, before_zone, after_zone, shot, zones = ARGV; File.write(path, JSON.pretty_generate({"id"=>id,"action"=>action,"fixture_id"=>fixture,"expected_before"=>before_zone,"expected_after"=>after_zone,"before_screenshot"=>shot,"before_zones_path"=>zones,"started_at"=>Time.now.utc.iso8601})+"\n")' \
    "$pending" "$case_id" "$action" "$fixture" "$expected_before" "$expected_after" "$before_screenshot" "$before_zones"
  echo "▶ $case_id started for $fixture ($expected_before → $expected_after)."
  echo "   Now perform the real $action input, then run: scripts/air_ir_test.sh finish $case_id"
}

finish_case() {
  local raw_case_id="${1:-}"
  local case_id
  case_id="$(canonical_case_id "$raw_case_id")" || { echo "❌ unknown case: $raw_case_id"; exit 1; }
  local run_dir pending
  run_dir="$(ensure_air_run_dir)"
  pending="$run_dir/$case_id.pending.json"
  [ -f "$pending" ] || { echo "❌ missing pending case: $pending"; exit 1; }
  local action fixture expected_before expected_after before_screenshot before_zones started_at
  action="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["action"]' "$pending")"
  fixture="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["fixture_id"]' "$pending")"
  expected_before="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["expected_before"]' "$pending")"
  expected_after="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["expected_after"]' "$pending")"
  before_screenshot="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["before_screenshot"]' "$pending")"
  before_zones="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["before_zones_path"]' "$pending")"
  started_at="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["started_at"]' "$pending")"
  local case_dir after_zones after_screenshot log_case actual_after input_path
  case_dir="$run_dir/$case_id"
  after_zones="$case_dir/after-zones.txt"
  after_screenshot="$case_dir/after.png"
  log_case="$case_dir/log-excerpt.txt"
  capture_zones > "$after_zones"
  actual_after="$(normalize_zone "$(zone_for_fixture "$after_zones" "$fixture")")"
  if [ "$actual_after" != "$expected_after" ]; then
    echo "❌ $fixture expected in $expected_after after $case_id, got ${actual_after:-missing}"
    exit 1
  fi
  screencapture -x "$after_screenshot"
  grep -iE "MOVE ICON START|toHidden=|task started|moveMenuBarIcon|Icon frame AFTER|Move complete|targetLane|classifyItems|Accepting cached" "$LOG_PATH" 2>/dev/null | tail -80 > "$log_case" || true
  if [ ! -s "$log_case" ]; then
    echo "❌ no move log excerpt found in $LOG_PATH"
    exit 1
  fi
  if [ "$action" = "menu" ]; then
    input_path="hotkey -> click All -> filter -> right_click_menu -> click Move row"
  else
    input_path="hotkey -> click All -> filter -> drag_tile"
  fi
  ruby -rjson -rtime -e '
    pending_path, case_path, before_zone, after_zone, after_screenshot, after_zones, log_path, input_path = ARGV
    pending = JSON.parse(File.read(pending_path))
    log_excerpt = File.readlines(log_path, chomp: true).last(40)
    payload = pending.merge(
      "before_zone" => before_zone,
      "after_zone" => after_zone,
      "after_screenshot" => after_screenshot,
      "after_zones_path" => after_zones,
      "log_path" => log_path,
      "log_excerpt" => log_excerpt,
      "input_path" => input_path,
      "finished_at" => Time.now.utc.iso8601
    )
    File.write(case_path, JSON.pretty_generate(payload) + "\n")
  ' "$pending" "$run_dir/$case_id.case.json" "$expected_before" "$actual_after" "$after_screenshot" "$after_zones" "$log_case" "$input_path"
  trash "$pending" 2>/dev/null || rm -f "$pending"
  write_air_receipt "$run_dir"
}

validate_receipt() {
  ruby -rjson - "$AIR_RECEIPT" <<'RUBY'
path = ARGV.fetch(0)
abort "missing receipt: #{path}" unless File.file?(path)
payload = JSON.parse(File.read(path))
abort "receipt status is #{payload['status'].inspect}, expected passed" unless payload['status'] == 'passed'
abort 'receipt did not use built-in display' unless payload.dig('display', 'built_in') == true
abort 'receipt did not launch through sane_test.rb' unless payload['launch_method'].to_s.include?('sane_test.rb')
required = %w[
  menu-hidden-visible
  menu-visible-alwaysHidden
  menu-alwaysHidden-hidden
  drag-visible-hidden
  drag-hidden-alwaysHidden
  drag-alwaysHidden-visible
]
cases = Array(payload['cases']).each_with_object({}) { |item, memo| memo[item['id'].to_s] = item }
missing = required - cases.keys
abort "missing case(s): #{missing.join(', ')}" unless missing.empty?
bad = cases.values.select do |item|
  item['fixture_id'].to_s !~ /SBF-[A-E]/ ||
    item['input_path'].to_s =~ /applescript|runScriptMove|move icon to/i ||
    Array(item['log_excerpt']).join("\n").strip.empty? ||
    !File.file?(item['before_screenshot'].to_s) ||
    !File.file?(item['after_screenshot'].to_s) ||
    !File.file?(item['before_zones_path'].to_s) ||
    !File.file?(item['after_zones_path'].to_s) ||
    !File.file?(item['log_path'].to_s)
end
abort "invalid case(s): #{bad.map { |item| item['id'] }.join(', ')}" unless bad.empty?
puts "✅ Air IR receipt valid: #{path}"
RUBY
}

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
       scripts/air_ir_test.sh zones | grep -i <iconname>
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
    run_dir="$(new_air_run_dir)"
    echo "▶ Enabling local-UI (sanctioned bypass for computer-use on the Air)…"
    touch "$PROJECT_DIR/.claude/bypass_active.json"
    echo "▶ Starting live debug log → $LOG_PATH"
    pkill -f "log stream --level debug --predicate.*com.sanebar.app" 2>/dev/null
    : > "$LOG_PATH"
    nohup log stream --level debug --predicate "$SUBSYS" --style compact > "$LOG_PATH" 2>&1 &
    echo "   log stream PID: $!"
    echo "▶ Running app:"; pgrep -lx SaneBar || echo "   (not detected — check /Applications/SaneBar.app)"
    echo "▶ Air IR receipt run: $run_dir"
    print_recipe
    echo "When done:  scripts/air_ir_test.sh validate && scripts/air_ir_test.sh teardown"
    ;;
  start)
    start_case "${2:-}" "${3:-}"
    ;;
  finish)
    finish_case "${2:-}"
    ;;
  validate)
    validate_receipt
    ;;
  zones)
    capture_zones
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
    trash "$AIR_STATE" 2>/dev/null || rm -f "$AIR_STATE"
    echo "✅ Done. Single instance:"; pgrep -lx SaneBar
    echo "   (Restore the notarized release build via the release pipeline when finished testing.)"
    ;;
  *)
    echo "usage: scripts/air_ir_test.sh {setup|start|finish|validate|zones|logs|moves|teardown}"; exit 1
    ;;
esac
