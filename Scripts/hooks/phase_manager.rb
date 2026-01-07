# frozen_string_literal: true

# ==============================================================================
# Phase Manager - Multi-phase SaneLoop orchestration
# ==============================================================================
# Big tasks get broken into phases. Each phase is its own SaneLoop.
# Each phase builds on the previous phase's learnings.
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
PHASE_STATE_FILE = File.join(PROJECT_DIR, '.claude/phase_state.json')
PHASE_OUTPUT_DIR = File.join(PROJECT_DIR, '.claude/phases')

STANDARD_PHASES = [
  {
    id: :research,
    name: 'RESEARCH',
    description: 'Gather information from all sources',
    criteria: [
      'Memory MCP checked for past bugs/patterns',
      'API docs verified (apple-docs, context7)',
      'Web search for patterns/solutions',
      'Local codebase explored',
      'External GitHub repos researched'
    ],
    output_file: 'phase_1_research.md',
    next_phase: :plan
  },
  {
    id: :plan,
    name: 'PLAN',
    description: 'Create hypotheses and implementation approach',
    criteria: [
      'Each feature has 2+ implementation approaches',
      'Pros/cons documented for each approach',
      'Recommended approach selected with rationale',
      'Edge cases identified upfront',
      'User approves the plan'
    ],
    output_file: 'phase_2_plan.md',
    input_from: 'phase_1_research.md',
    next_phase: :implement
  },
  {
    id: :implement,
    name: 'IMPLEMENT',
    description: 'Write the code following the approved plan',
    criteria: [
      'All planned features implemented',
      'Build passes without errors',
      'No new warnings introduced',
      'Code follows project patterns',
      'Basic tests added'
    ],
    output_file: 'phase_3_implement.md',
    input_from: 'phase_2_plan.md',
    next_phase: :test
  },
  {
    id: :test,
    name: 'TEST',
    description: 'Find and fix edge cases repeatedly',
    criteria: [
      'All existing tests pass',
      '3+ edge cases tested per feature',
      'No edge case failures remain',
      'Manual test steps documented',
      'User can verify with simple clicks'
    ],
    output_file: 'phase_4_test.md',
    input_from: 'phase_3_implement.md',
    next_phase: :polish
  },
  {
    id: :polish,
    name: 'POLISH',
    description: 'UI/UX refinements and details',
    criteria: [
      'Font sizes >= 13pt everywhere',
      'No hidden features - all discoverable',
      'Consistent styling throughout',
      'Error messages are helpful',
      'Everything looks beautiful'
    ],
    output_file: 'phase_5_polish.md',
    input_from: 'phase_4_test.md',
    next_phase: nil
  }
].freeze

module PhaseManager
  class << self
    def load_state
      return default_state unless File.exist?(PHASE_STATE_FILE)
      JSON.parse(File.read(PHASE_STATE_FILE), symbolize_names: true)
    rescue StandardError
      default_state
    end

    def save_state(state)
      FileUtils.mkdir_p(File.dirname(PHASE_STATE_FILE))
      File.write(PHASE_STATE_FILE, JSON.pretty_generate(state))
    end

    def default_state
      { active: false, current_phase: nil, phases_completed: [], task_description: nil, started_at: nil }
    end

    def start_phased_task(task_description)
      FileUtils.mkdir_p(PHASE_OUTPUT_DIR)
      state = {
        active: true,
        current_phase: :research,
        phases_completed: [],
        task_description: task_description,
        started_at: Time.now.iso8601
      }
      save_state(state)
      STANDARD_PHASES.first
    end

    def current_phase
      state = load_state
      return nil unless state[:active] && state[:current_phase]
      STANDARD_PHASES.find { |p| p[:id] == state[:current_phase].to_sym }
    end

    def complete_phase(phase_output)
      state = load_state
      return false unless state[:active]
      phase = current_phase
      return false unless phase

      output_path = File.join(PHASE_OUTPUT_DIR, phase[:output_file])
      File.write(output_path, phase_output)

      state[:phases_completed] << { phase: phase[:id], completed_at: Time.now.iso8601, output_file: phase[:output_file] }

      if phase[:next_phase]
        state[:current_phase] = phase[:next_phase]
        save_state(state)
        STANDARD_PHASES.find { |p| p[:id] == phase[:next_phase] }
      else
        state[:active] = false
        state[:completed_at] = Time.now.iso8601
        save_state(state)
        nil
      end
    end

    def get_previous_output
      phase = current_phase
      return nil unless phase && phase[:input_from]
      input_path = File.join(PHASE_OUTPUT_DIR, phase[:input_from])
      return nil unless File.exist?(input_path)
      File.read(input_path)
    end

    def active?
      load_state[:active] == true
    end

    def status
      state = load_state
      return "No active phased task" unless state[:active]
      phase = current_phase
      completed = state[:phases_completed]&.length || 0
      "Phase #{completed + 1}/5: #{phase[:name]} - #{phase[:description]}"
    end

    def saneloop_spec
      phase = current_phase
      return nil unless phase
      criteria = phase[:criteria].map.with_index { |c, i| "#{i + 1}. [ ] #{c}" }.join("\n")
      "## Phase: #{phase[:name]}\n#{phase[:description]}\n\n### Criteria\n#{criteria}\n\n### Input\n#{phase[:input_from] || 'None'}\n\n### Output\n.claude/phases/#{phase[:output_file]}"
    end

    def abort(reason = nil)
      state = load_state
      state[:active] = false
      state[:aborted_at] = Time.now.iso8601
      state[:abort_reason] = reason
      save_state(state)
    end
  end
end
