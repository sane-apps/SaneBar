#!/usr/bin/env ruby
# frozen_string_literal: true

# Marketing Screenshot Automation (Current UI)
#
# Usage:
#   ./scripts/marketing_screenshots.rb --list
#   ./scripts/marketing_screenshots.rb --shot icon-panel
#   ./scripts/marketing_screenshots.rb
#
# Notes:
# - This script captures CURRENT settings/image targets used by docs/index.html.
# - Some shots depend on app state (for example second-menu-bar requires browse mode = Second Menu Bar).

require 'fileutils'

APP_NAME = 'SaneBar'

def resolve_screenshot_tool
  env_override = ENV['SANEBAR_SCREENSHOT_TOOL']
  return env_override if env_override && !env_override.empty? && File.executable?(env_override)

  from_path = `command -v screenshot 2>/dev/null`.strip
  return from_path unless from_path.empty?

  candidates = %w[
    ~/Library/Python/3.13/bin/screenshot
    ~/Library/Python/3.12/bin/screenshot
    ~/Library/Python/3.11/bin/screenshot
    ~/Library/Python/3.10/bin/screenshot
    ~/Library/Python/3.9/bin/screenshot
  ].map { |p| File.expand_path(p) }

  candidates.find { |path| File.executable?(path) }
end

SHOTS = {
  'settings-general' => {
    title: 'General',
    filename: 'settings-general.png',
    description: 'General tab (Browse Icons + startup/update/license sections)'
  },
  'settings-rules' => {
    title: 'Rules',
    filename: 'settings-rules.png',
    description: 'Rules tab (rehide, reveal gestures, triggers)'
  },
  'settings-appearance' => {
    title: 'Appearance',
    filename: 'settings-appearance.png',
    description: 'Appearance tab (icon style, divider, layout, spacing)'
  },
  'settings-shortcuts' => {
    title: 'Shortcuts',
    filename: 'settings-shortcuts.png',
    description: 'Shortcuts tab (hotkeys + automation)'
  },
  'settings-help' => {
    title: 'About',
    filename: 'settings-about.png',
    description: 'About tab (GitHub, licenses, bug report, issues)'
  },
  'browse-settings' => {
    title: 'General',
    filename: 'browse-settings.png',
    description: 'General tab focused on Browse Icons section'
  },
  'icon-panel' => {
    title: 'Icon Panel',
    filename: 'icon-panel.png',
    description: 'Browse Icons window in Icon Panel mode',
    min_height: 300
  },
  'second-menu-bar' => {
    title: nil,
    filename: 'second-menu-bar.png',
    description: 'Browse Icons in Second Menu Bar mode (ensure this is the only SaneBar window before capture)',
    min_height: 120
  }
}.freeze

ONBOARDING_SYNC = {
  'icon-panel.png' => 'Resources/Assets.xcassets/OnboardingIconPanel.imageset/icon-panel.png',
  'second-menu-bar.png' => 'Resources/Assets.xcassets/OnboardingSecondMenuBar.imageset/second-menu-bar.png',
  'browse-settings.png' => 'Resources/Assets.xcassets/OnboardingBrowseSettings.imageset/browse-settings.png'
}.freeze

def ensure_prereqs
  tool = screenshot_tool
  unless tool && File.executable?(tool)
    warn "❌ screenshot tool not found (checked PATH and ~/Library/Python/*/bin/screenshot)"
    return false
  end
  FileUtils.mkdir_p(output_dir)
  true
end

def list_shots
  warn 'Available screenshots:'
  SHOTS.each do |name, config|
    warn "  #{name.ljust(20)} - #{config[:description]}"
  end
  warn "\nTip: Open the target SaneBar window/state first, then run --shot NAME."
end

def capture(name, config)
  output = File.join(output_dir, config[:filename])
  temp_output = "#{output}.tmp.png"
  FileUtils.rm_f(temp_output)

  cmd = [screenshot_tool, APP_NAME, '-s']
  cmd += ['-t', config[:title]] if config[:title]
  cmd += ['-f', temp_output]

  warn "📸 Capturing #{name} -> #{config[:filename]}"
  ok = system(*cmd)
  unless ok
    warn "   ❌ Capture failed for #{name}. Ensure the target window/state is visible."
    return false
  end

  width, height = read_dimensions(temp_output)
  min_height = config[:min_height]
  if min_height && (height.nil? || height < min_height)
    warn "   ❌ Rejected #{name}: capture height #{height || 'unknown'} is below minimum #{min_height}px."
    warn "      This usually means a collapsed line capture. Keep the existing screenshot and retry with the target window open."
    FileUtils.rm_f(temp_output)
    return false
  end

  FileUtils.mv(temp_output, output)
  warn "   ✅ #{output}"
  true
end

def read_dimensions(path)
  output = `sips -g pixelWidth -g pixelHeight "#{path}" 2>/dev/null`
  width = output[/pixelWidth:\s*(\d+)/, 1]&.to_i
  height = output[/pixelHeight:\s*(\d+)/, 1]&.to_i
  [width, height]
end

def sync_onboarding
  return true unless onboarding_sync_enabled?

  ONBOARDING_SYNC.each do |src_name, dest_rel|
    src = File.join(output_dir, src_name)
    dest = File.expand_path("../#{dest_rel}", __dir__)
    next unless File.exist?(src)

    FileUtils.cp(src, dest)
    warn "🔁 Synced #{src_name} -> #{dest_rel}"
  end
  true
end

def capture_all
  success = 0
  SHOTS.each do |name, config|
    success += 1 if capture(name, config)
  end
  sync_onboarding
  warn "\nDone: #{success}/#{SHOTS.size} captured"
  success == SHOTS.size
end

def capture_one(name)
  config = SHOTS[name]
  unless config
    warn "❌ Unknown shot: #{name}"
    list_shots
    return false
  end

  result = capture(name, config)
  sync_onboarding
  result
end

def output_dir
  @output_dir = nil if ENV['SANEBAR_SCREENSHOT_RESET_CACHE'] == '1'
  @output_dir ||= begin
    override = ENV['SANEBAR_SCREENSHOT_OUTPUT_DIR']
    base = override && !override.empty? ? override : File.expand_path('../docs/images', __dir__)
    File.expand_path(base)
  end
end

def screenshot_tool
  @screenshot_tool = nil if ENV['SANEBAR_SCREENSHOT_RESET_CACHE'] == '1'
  @screenshot_tool ||= resolve_screenshot_tool
end

def onboarding_sync_enabled?
  ENV['SANEBAR_SCREENSHOT_SKIP_SYNC'] != '1'
end

def run_cli(argv)
  return 1 unless ensure_prereqs

  case argv[0]
  when '--list', '-l'
    list_shots
    0
  when '--shot', '-s'
    capture_one(argv[1]) ? 0 : 1
  else
    capture_all ? 0 : 1
  end
end

if $PROGRAM_NAME == __FILE__
  exit(run_cli(ARGV))
end
