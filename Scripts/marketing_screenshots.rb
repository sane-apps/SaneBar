#!/usr/bin/env ruby
# frozen_string_literal: true

# Marketing Screenshot Automation
# Reusable process for capturing app screenshots for marketing materials
#
# Usage:
#   ./Scripts/marketing_screenshots.rb              # Capture all SaneBar screenshots
#   ./Scripts/marketing_screenshots.rb --list       # List available shots
#   ./Scripts/marketing_screenshots.rb --shot NAME  # Capture specific shot
#
# Requirements:
#   pip3 install screenshot
#   brew install imagemagick (for polish effects)

require 'fileutils'
require 'json'

SCREENSHOT_TOOL = '/Users/sj/Library/Python/3.13/bin/screenshot'
OUTPUT_DIR = File.expand_path('../marketing/screenshots', __dir__)
TEMP_DIR = '/tmp/marketing_screenshots'

# Screenshot definitions - customize per app
# Each shot defines: app name, window title filter, output filename, description
# Optional: tab (toolbar button to click), scroll (0.0-1.0 scroll position)
SHOTS = {
  'settings-general' => {
    app: 'SaneBar',
    tab: 'General',
    scroll: 0.0,
    filename: 'general-settings.png',
    description: 'General settings tab'
  },
  'settings-shortcuts' => {
    app: 'SaneBar',
    tab: 'Shortcuts',
    scroll: 0.0,
    filename: 'shortcuts-settings.png',
    description: 'Keyboard shortcuts tab'
  },
  'settings-advanced-top' => {
    app: 'SaneBar',
    tab: 'Advanced',
    scroll: 0.0,
    filename: 'advanced-settings-top.png',
    description: 'Advanced settings (Privacy & Auto-show)'
  },
  'settings-advanced-spacing' => {
    app: 'SaneBar',
    tab: 'Advanced',
    scroll: 0.5,
    filename: 'advanced-settings-spacing.png',
    description: 'Advanced settings (System Icon Spacing)'
  },
  'settings-about' => {
    app: 'SaneBar',
    tab: 'About',
    scroll: 0.0,
    filename: 'about-settings.png',
    description: 'About tab'
  },
  'find-icon' => {
    app: 'SaneBar',
    title: nil, # No navigation needed
    filename: 'find-icon-window.png',
    description: 'Find Icon search window'
  },
  # Menu bar shots - AUTOMATED via AppleScript commands
  'menubar-hidden' => {
    app: nil,
    region: 'menubar',
    sanebar_cmd: 'hide items',  # Ensure icons are hidden first
    filename: 'menubar-hidden.png',
    description: 'Menu bar with icons HIDDEN (clean look)'
  },
  'menubar-revealed' => {
    app: nil,
    region: 'menubar',
    sanebar_cmd: 'show hidden',  # Reveal icons first
    filename: 'menubar-revealed.png',
    description: 'Menu bar with icons REVEALED'
  }
}.freeze

# Control SaneBar via AppleScript
def sanebar_command(cmd)
  system('osascript', '-e', "tell application \"SaneBar\" to #{cmd}")
  sleep 0.5  # Wait for animation
end

# Capture just the menu bar region
def capture_menubar(filename)
  temp_file = "/tmp/menubar-full.png"

  # Capture full screen
  system('screencapture', '-x', temp_file)

  # Crop to menu bar (top 40 pixels, full width)
  # Get screen width first
  width = `system_profiler SPDisplaysDataType | grep Resolution | head -1`.match(/(\d+) x/)[1] rescue '2560'

  system('magick', temp_file,
         '-crop', "#{width}x50+0+0",  # Top 50px of screen
         '+repage',
         '-resize', '1200x>',  # Max 1200px wide for marketing
         filename)
end

# Navigate to a specific tab and scroll position
def navigate_to(app, tab: nil, scroll: nil)
  return unless tab || scroll

  script = %(
    tell application "System Events"
      tell process "#{app}"
  )

  if tab
    script += %(
        click button "#{tab}" of toolbar 1 of window 1
        delay 0.3
    )
  end

  if scroll
    script += %(
        tell scroll area 1 of group 1 of window 1
          tell scroll bar 1
            set value to #{scroll}
          end tell
        end tell
        delay 0.2
    )
  end

  script += %(
      end tell
    end tell
  )

  system('osascript', '-e', script)
end

def setup_dirs
  FileUtils.mkdir_p(OUTPUT_DIR)
  FileUtils.mkdir_p(TEMP_DIR)
end

def capture_screenshot(shot_name, shot_config)
  temp_file = File.join(TEMP_DIR, "#{shot_name}-raw.png")
  final_file = File.join(OUTPUT_DIR, shot_config[:filename])

  warn "📸 Capturing: #{shot_config[:description]}..."

  # Handle menu bar region capture differently
  if shot_config[:region] == 'menubar'
    # Execute SaneBar command first (hide/show icons)
    if shot_config[:sanebar_cmd]
      sanebar_command(shot_config[:sanebar_cmd])
      warn "   🎛️  Executed: tell SaneBar to #{shot_config[:sanebar_cmd]}"
    end
    capture_menubar(final_file)
    warn "   ✅ Saved: #{final_file}"
    return true
  end

  # Navigate to correct tab/scroll position first
  if shot_config[:tab] || shot_config[:scroll]
    navigate_to(shot_config[:app], tab: shot_config[:tab], scroll: shot_config[:scroll])
    warn "   🧭 Navigated to #{shot_config[:tab] || 'position'}"
  end

  # Build screenshot command
  cmd = [SCREENSHOT_TOOL, shot_config[:app], '-s'] # -s for shadow
  # Use tab name as title filter if we navigated to a tab
  title_filter = shot_config[:title] || shot_config[:tab]
  cmd += ['-t', title_filter] if title_filter
  cmd += ['-f', temp_file]

  success = system(*cmd)
  unless success
    warn "   ❌ Failed to capture #{shot_name}"
    return false
  end

  # Apply marketing polish with ImageMagick
  polish_screenshot(temp_file, final_file)

  warn "   ✅ Saved: #{final_file}"
  true
end

def polish_screenshot(input, output)
  # Add subtle enhancements for marketing
  # - Ensure consistent sizing
  # - Add slight shadow boost if needed
  system('magick', input,
         '-resize', '800x>', # Max width 800px for web
         '-quality', '95',
         output)
end

def list_shots
  warn "Available screenshots:"
  SHOTS.each do |name, config|
    warn "  #{name.ljust(20)} - #{config[:description]}"
  end
end

def capture_all
  setup_dirs

  warn "🎬 Marketing Screenshot Capture"
  warn "================================"
  warn ""
  warn "⚠️  Make sure the app windows are open and positioned!"
  warn ""

  success_count = 0
  SHOTS.each do |name, config|
    success_count += 1 if capture_screenshot(name, config)
  end

  warn ""
  warn "📊 Captured #{success_count}/#{SHOTS.size} screenshots"
  warn "📁 Output: #{OUTPUT_DIR}"
end

def capture_single(shot_name)
  unless SHOTS.key?(shot_name)
    warn "❌ Unknown shot: #{shot_name}"
    warn "   Use --list to see available shots"
    exit 1
  end

  setup_dirs
  capture_screenshot(shot_name, SHOTS[shot_name])
end

# Main
case ARGV[0]
when '--list', '-l'
  list_shots
when '--shot', '-s'
  capture_single(ARGV[1])
when '--help', '-h'
  warn "Usage: #{$PROGRAM_NAME} [--list | --shot NAME | --help]"
  warn "  (no args)    Capture all screenshots"
  warn "  --list       List available shots"
  warn "  --shot NAME  Capture specific shot"
else
  capture_all
end
