#!/usr/bin/env ruby
# frozen_string_literal: true

# SaneBar Button Map
# Maps every UI button/toggle to its corresponding action
#
# Usage: ./scripts/button_map.rb

require 'set'

CORE_PATH = File.expand_path('../Core', __dir__)
UI_PATH = File.expand_path('../UI', __dir__)

class ButtonMapper
  def initialize
    @buttons = []
    @bindings = {}
    @actions = {}
  end

  def scan
    scan_ui_bindings
    scan_objc_actions
    scan_core_functions
  end

  def scan_ui_bindings
    Dir.glob("#{UI_PATH}/**/*.swift").each do |file|
      content = File.read(file)
      filename = File.basename(file)

      # Find SwiftUI Toggles with bindings
      content.scan(/(?:Toggle|CompactToggle).*?isOn:\s*\$?(\w+(?:\.\w+)*)/).each do |match|
        binding = match[0]
        @buttons << {
          type: 'Toggle',
          binding: binding,
          file: filename,
          line: find_line(content, binding)
        }
      end

      # Find Button actions
      content.scan(/Button\s*\(\s*["']([^"']+)["']\s*\)\s*\{([^}]+)\}/).each do |match|
        label, action = match
        @buttons << {
          type: 'Button',
          label: label,
          action: action.strip.gsub(/\s+/, ' ')[0..80],
          file: filename
        }
      end

      # Find action: selectors
      content.scan(/action:\s*#selector\((\w+)\)/).each do |match|
        @actions[match[0]] = filename
      end
    end
  end

  def scan_objc_actions
    Dir.glob("#{CORE_PATH}/**/*.swift").each do |file|
      content = File.read(file)
      filename = File.basename(file)

      content.scan(/@objc\s+(?:\w+\s+)?func\s+(\w+)\s*\([^)]*\)[^{]*\{([\s\S]*?)(?=\n    (?:@objc|func|var|let|private|internal|public|\/\/\s*MARK)|\n\})/).each do |match|
        func_name = match[0]
        body = match[1]
        calls = body.scan(/(\w+)\s*\(/).flatten.uniq

        @actions[func_name] = {
          file: filename,
          calls: calls.reject { |c| %w[if for while guard return let var print logger Task].include?(c) }
        }
      end
    end
  end

  def scan_core_functions
    # Map key functions that handle triggers
    key_functions = %w[
      toggleHiddenItems showHiddenItems hideHiddenItems showHiddenItemsNow
      show hide toggle scheduleRehide cancelRehide
      handleAppLaunch checkBatteryLevel handleNetworkChange
      authenticate
    ]

    Dir.glob("#{CORE_PATH}/**/*.swift").each do |file|
      content = File.read(file)
      filename = File.basename(file)

      key_functions.each do |func|
        if content.include?("func #{func}")
          @actions[func] ||= { file: filename, calls: [] }
          @actions[func][:file] = filename
        end
      end
    end
  end

  def find_line(content, search)
    content.lines.each_with_index do |line, idx|
      return idx + 1 if line.include?(search)
    end
    nil
  end

  def report
    puts "=" * 60
    puts "SANEBAR BUTTON → ACTION MAP"
    puts "=" * 60
    puts

    puts "## UI TOGGLES (Settings bindings)"
    puts "-" * 40
    @buttons.select { |b| b[:type] == 'Toggle' }.each do |btn|
      puts "• #{btn[:binding]}"
      puts "  File: #{btn[:file]}:#{btn[:line]}"
      trace_binding(btn[:binding])
      puts
    end

    puts "\n## OBJC BUTTON HANDLERS"
    puts "-" * 40
    @actions.each do |name, info|
      next unless info.is_a?(Hash) && info[:calls]
      puts "• #{name}() → #{info[:file]}"
      puts "  Calls: #{info[:calls].join(', ')}" unless info[:calls].empty?
    end

    puts "\n## CRITICAL FLOW PATHS"
    puts "-" * 40
    puts <<~FLOWS
    1. LEFT-CLICK on SaneBar icon:
       statusItemClicked → toggleHiddenItems → [auth check] → hidingService.toggle()

    2. RIGHT-CLICK menu → Settings:
       openSettings → SettingsOpener.open()

    3. Toggle "Require password":
       $menuBarManager.settings.requireAuthToShowHiddenIcons
       → settings sink → [no reveal action]

    4. Hover trigger:
       HoverService.onTrigger → showHiddenItemsNow(trigger: .automation) → [auth check]

    5. App launch trigger:
       TriggerService.handleAppLaunch → showHiddenItems → showHiddenItemsNow → [auth check]

    6. Battery trigger:
       TriggerService.checkBatteryLevel → showHiddenItems → showHiddenItemsNow → [auth check]

    7. Network trigger:
       NetworkTriggerService.handleNetworkChange → showHiddenItems → showHiddenItemsNow → [auth check]
    FLOWS
  end

  def trace_binding(binding)
    # Trace what happens when this binding changes
    parts = binding.split('.')
    if parts.include?('settings')
      setting = parts.last
      puts "  → Changes settings.#{setting}"
      puts "  → Triggers $settings sink in MenuBarManager"
      puts "  → Calls: updateSpacers, updateAppearance, updateNetworkTrigger, etc."
    end
  end
end

mapper = ButtonMapper.new
mapper.scan
mapper.report
