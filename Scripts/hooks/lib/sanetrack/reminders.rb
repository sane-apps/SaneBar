# frozen_string_literal: true

require_relative '../../core/state_manager'
require 'time'

module SaneTrack
  module Reminders
    REMINDER_COOLDOWN = 300

    def self.should_remind?(reminder_type)
      reminders = StateManager.get(:reminders) || {}
      last_at = reminders["#{reminder_type}_at".to_sym]
      return true unless last_at

      begin
        time_since = Time.now - Time.parse(last_at)
        time_since >= REMINDER_COOLDOWN
      rescue ArgumentError
        true
      end
    end

    def self.record_reminder(reminder_type)
      StateManager.update(:reminders) do |r|
        r ||= {}
        r["#{reminder_type}_at".to_sym] = Time.now.iso8601
        r["#{reminder_type}_count".to_sym] = (r["#{reminder_type}_count".to_sym] || 0) + 1
        r
      end
    end

    def self.emit_rewind_reminder(error_count)
      return unless should_remind?(:rewind)

      record_reminder(:rewind)

      warn ''
      if error_count >= 2
        warn '🔄 CONSIDER /rewind - Multiple errors suggest research before retry'
        warn '   Press Esc+Esc to rollback code AND conversation to last checkpoint'
      else
        warn '💡 TIP: /rewind can rollback this change if needed (Esc+Esc shortcut)'
      end
      warn ''
    end

    def self.emit_context_reminder(edit_count)
      return unless edit_count % 5 == 0 && edit_count > 0
      return unless should_remind?(:context)

      record_reminder(:context)

      warn ''
      warn "💡 TIP: After #{edit_count} edits - try /context to visualize token usage"
      warn '   Helps identify what\'s consuming your context window'
      warn ''
    end

    def self.emit_explore_reminder(tool_name, tool_input)
      return unless %w[Grep Glob].include?(tool_name)

      pattern = tool_input['pattern'] || tool_input[:pattern] || ''
      return unless pattern.include?('**') || pattern.length > 30

      return unless should_remind?(:explore)

      record_reminder(:explore)

      warn ''
      warn '💡 TIP: For large codebase searches, use Task with subagent_type: Explore'
      warn '   Haiku-powered exploration saves context tokens'
      warn ''
    end
  end
end
