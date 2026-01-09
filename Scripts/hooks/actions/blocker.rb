#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Blocker Action
# ==============================================================================
# Handles blocking enforcement decisions. Emits formatted error message
# to stderr and exits with code 2 to prevent tool execution.
#
# Usage:
#   Blocker.block(result)  # result is DetectorResult
#   Blocker.block_with_message(rule: 'RULE', message: 'why', fix: 'how')
# ==============================================================================

require_relative 'logger'

module Blocker
  module_function

  # Block with a DetectorResult object
  def block(result)
    emit_message(
      rule: result.rule || 'ENFORCEMENT',
      message: result.message,
      fix: result.details[:fix],
      details: result.details
    )

    Logger.log_block(
      rule: result.rule,
      message: result.message,
      detector: result.detector_name,
      details: result.details
    )

    exit 2
  end

  # Block with explicit parameters
  def block_with_message(rule:, message:, fix: nil, details: {})
    emit_message(rule: rule, message: message, fix: fix, details: details)

    Logger.log_block(
      rule: rule,
      message: message,
      detector: details[:detector],
      details: details
    )

    exit 2
  end

  # Emit formatted block message to stderr
  def emit_message(rule:, message:, fix: nil, details: {})
    warn ''
    warn "🔴 BLOCKED: #{rule}"
    warn "   #{message}"

    if fix
      warn ''
      warn "   Fix: #{fix}"
    end

    # Additional context if present
    if details[:missing]
      warn "   Missing: #{Array(details[:missing]).join(', ')}"
    end

    if details[:current] && details[:limit]
      warn "   Current: #{details[:current]} / Limit: #{details[:limit]}"
    end

    warn ''
  end
end
