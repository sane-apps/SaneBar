#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Warner Action
# ==============================================================================
# Handles warning enforcement decisions. Emits formatted warning message
# to stderr but allows tool execution (exit 0).
#
# Usage:
#   Warner.warn(result)  # result is DetectorResult
#   Warner.warn_all(results)  # array of DetectorResults
# ==============================================================================

require_relative 'logger'

module Warner
  module_function

  # Warn with a single DetectorResult
  def warn_single(result)
    emit_warning(
      rule: result.rule || 'WARNING',
      message: result.message,
      details: result.details
    )

    Logger.log_warning(
      rule: result.rule,
      message: result.message,
      detector: result.detector_name,
      details: result.details
    )
  end

  # Warn with multiple results
  def warn_all(results)
    return if results.empty?

    warn ''
    results.each do |result|
      warn "⚠️  #{result.rule || 'Warning'}: #{result.message}"

      Logger.log_warning(
        rule: result.rule,
        message: result.message,
        detector: result.detector_name,
        details: result.details
      )
    end
    warn ''
  end

  # Emit formatted warning to stderr
  def emit_warning(rule:, message:, details: {})
    warn ''
    warn "⚠️  #{rule}: #{message}"

    if details[:current] && details[:projected]
      warn "   Progress: #{details[:current]} → #{details[:projected]}"
    end

    warn ''
  end

  # Emit info message (not a warning, just informational)
  def info(message)
    warn "ℹ️  #{message}"
  end
end
