#!/usr/bin/env ruby
# frozen_string_literal: true

# Tier Tests: Easy, Hard, Villain
# Tests ACTUAL hook behavior, not just helper functions
#
# Run: ruby scripts/hooks/test/tier_tests.rb

require_relative 'tiers/framework'
require_relative 'tiers/saneprompt_test'
require_relative 'tiers/sanetools_test'
require_relative 'tiers/sanetrack_test'
require_relative 'tiers/sanestop_test'
require_relative 'tiers/integration_test'

def run_all_tests
  warn "=" * 60
  warn "TIER TESTS: Easy, Hard, Villain"
  warn "=" * 60

  results = []
  results << TierTests.test_saneprompt
  results << TierTests.test_sanetools
  results << TierTests.test_sanetrack
  results << TierTests.test_sanestop
  results << TierTests.test_integration

  warn "\n" + "=" * 60
  warn "SUMMARY"
  warn "=" * 60

  total_passed = 0
  total_failed = 0
  total_skipped = 0

  results.each do |r|
    total_passed += r[:passed]
    total_failed += r[:failed]
    total_skipped += r[:skipped]

    status = r[:failed] == 0 ? '✅' : '❌'
    warn "#{status} #{r[:hook].upcase}: #{r[:passed]}/#{r[:total]} " \
         "(Easy: #{r[:by_tier][:easy]}, Hard: #{r[:by_tier][:hard]}, Villain: #{r[:by_tier][:villain]})"
  end

  warn ""
  warn "TOTAL: #{total_passed}/#{total_passed + total_failed} passed, #{total_skipped} skipped"

  if total_failed > 0
    warn "\n#{total_failed}TESTS FAILED - Hooks need improvement"
    exit 1
  else
    warn "\nALL TESTS PASSED"
    exit 0
  end
end

if ARGV.include?('--self-test') || ARGV.empty?
  run_all_tests
end
