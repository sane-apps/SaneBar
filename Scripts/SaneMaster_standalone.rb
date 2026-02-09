#!/usr/bin/env ruby
# frozen_string_literal: true

# SaneMaster standalone — minimal build tool for external contributors.
# The full SaneMaster lives in SaneProcess infra (internal development).

require "open3"
require "fileutils"

PROJECT_ROOT = File.expand_path("..", __dir__)
XCODEPROJ = File.join(PROJECT_ROOT, "SaneBar.xcodeproj")
SCHEME = "SaneBar"

def run(cmd, label = nil)
  warn "=> #{label || cmd}"
  stdout, stderr, status = Open3.capture3(cmd, chdir: PROJECT_ROOT)
  unless status.success?
    warn stderr unless stderr.empty?
    warn stdout unless stdout.empty?
    abort "FAILED: #{label || cmd}"
  end
  warn stdout unless stdout.empty?
  stdout
end

def build(config = "Debug")
  run(
    "xcodebuild -project #{XCODEPROJ} -scheme #{SCHEME} " \
    "-configuration #{config} -arch arm64 build",
    "Build (#{config})"
  )
end

def test
  run(
    "xcodebuild -project #{XCODEPROJ} -scheme #{SCHEME} " \
    "-configuration Debug -arch arm64 test",
    "Test"
  )
end

def verify
  build
  test
  warn "\nAll good."
end

def test_mode
  build
  app = Dir.glob(File.join(PROJECT_ROOT, "build/**/SaneBar.app")).first
  app ||= Dir.glob(File.expand_path("~/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/SaneBar.app")).first
  abort "Could not find built SaneBar.app" unless app
  system("killall SaneBar 2>/dev/null")
  sleep 0.5
  system("open '#{app}'")
  warn "Launched #{app}"
end

def usage
  warn <<~HELP
    SaneMaster standalone (external contributor mode)

    Usage: ./scripts/SaneMaster.rb <command>

    Commands:
      build       Build Debug configuration
      test        Run unit tests
      verify      Build + test
      test_mode   Build, kill existing, launch app
      help        Show this message
  HELP
end

case ARGV[0]
when "build"      then build
when "test"       then test
when "verify"     then verify
when "test_mode"  then test_mode
when "help", nil  then usage
else
  warn "Unknown command: #{ARGV[0]}"
  usage
  exit 1
end
