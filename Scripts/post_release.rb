#!/usr/bin/env ruby
# frozen_string_literal: true

# Post-Release Script for SaneBar
# Updates appcast.xml after a GitHub release is created
#
# Usage:
#   ./scripts/post_release.rb                    # Auto-detect latest release
#   ./scripts/post_release.rb --version 1.0.15   # Specific version
#   ./scripts/post_release.rb --dry-run          # Preview without changes

require 'json'
require 'open3'
require 'date'
require 'fileutils'

class PostRelease
  APP_NAME = 'SaneBar'
  REPO = 'sane-apps/SaneBar'
  APPCAST_PATH = File.expand_path('../docs/appcast.xml', __dir__)
  CHANGELOG_PATH = File.expand_path('../CHANGELOG.md', __dir__)

  def initialize(version: nil, dry_run: false)
    @version = version
    @dry_run = dry_run
    @errors = []
  end

  def run
    puts "\n#{'=' * 60}"
    puts "POST-RELEASE AUTOMATION"
    puts "#{'=' * 60}\n\n"

    # Step 1: Determine version
    @version ||= detect_latest_release
    unless @version
      error "Could not detect latest release. Use --version X.Y.Z"
      return false
    end
    puts "📦 Version: #{@version}"

    # Step 2: Check if GitHub release exists
    release_info = get_github_release(@version)
    unless release_info
      error "GitHub release v#{@version} not found"
      return false
    end
    puts "✅ GitHub release found: v#{@version}"

    # Step 3: Download DMG and get info
    dmg_url = release_info[:dmg_url]
    unless dmg_url
      error "No DMG found in release v#{@version}"
      return false
    end
    puts "📥 DMG URL: #{dmg_url}"

    dmg_info = download_and_analyze_dmg(dmg_url)
    unless dmg_info
      error "Failed to download/analyze DMG"
      return false
    end
    puts "📊 DMG Size: #{dmg_info[:size]} bytes"

    # Step 4: Generate EdDSA signature
    signature = generate_signature(dmg_info[:path])
    unless signature
      error "Failed to generate EdDSA signature"
      return false
    end
    puts "🔐 Signature: #{signature[0..40]}..."

    # Step 5: Get build number from version
    build_number = version_to_build(@version)
    puts "🏗️  Build: #{build_number}"

    # Step 6: Check if already in appcast
    if version_in_appcast?(@version)
      puts "\n⚠️  Version #{@version} already in appcast.xml"
      print "   Overwrite? [y/N]: "
      return false unless $stdin.gets&.strip&.downcase == 'y'
    end

    # Step 7: Generate appcast entry
    entry = generate_appcast_entry(
      version: @version,
      build: build_number,
      size: dmg_info[:size],
      signature: signature,
      url: dmg_url
    )

    puts "\n📝 Generated appcast entry:"
    puts "-" * 40
    puts entry
    puts "-" * 40

    # Step 8: Update appcast.xml
    if @dry_run
      puts "\n🔍 DRY RUN - No changes made"
    else
      update_appcast(entry)
      puts "\n✅ Updated appcast.xml"
    end

    # Step 9: Cleanup
    File.delete(dmg_info[:path]) if dmg_info[:path] && File.exist?(dmg_info[:path])

    # Step 10: Summary
    puts "\n#{'=' * 60}"
    puts "RELEASE CHECKLIST"
    puts "#{'=' * 60}"
    puts "✅ GitHub release v#{@version} exists"
    puts "✅ DMG downloaded and verified"
    puts "✅ EdDSA signature generated"
    puts @dry_run ? "⏸️  Appcast update skipped (dry run)" : "✅ appcast.xml updated"
    puts ""
    puts "Next steps:"
    puts "  1. git add docs/appcast.xml"
    puts "  2. git commit -m 'chore: update appcast for v#{@version}'"
    puts "  3. git push"
    puts "  4. Verify at: https://sanebar.com/appcast.xml"
    puts "#{'=' * 60}\n"

    true
  end

  private

  def detect_latest_release
    output, status = Open3.capture2('gh', 'release', 'list', '--repo', REPO, '--limit', '1')
    return nil unless status.success?

    # Parse: "SaneBar v1.0.15    Latest  v1.0.15  2026-01-23T18:00:38Z"
    match = output.match(/v?(\d+\.\d+\.\d+)/)
    match ? match[1] : nil
  end

  def get_github_release(version)
    output, status = Open3.capture2('gh', 'release', 'view', "v#{version}", '--repo', REPO, '--json', 'assets,tagName')
    return nil unless status.success?

    data = JSON.parse(output)
    assets = data['assets'] || []
    dmg_asset = assets.find { |a| a['name'].end_with?('.dmg') }

    {
      tag: data['tagName'],
      dmg_url: dmg_asset ? dmg_asset['url'] : nil
    }
  rescue JSON::ParserError
    nil
  end

  def download_and_analyze_dmg(url)
    tmp_path = "/tmp/#{APP_NAME}-release.dmg"

    puts "   Downloading DMG..."
    _, status = Open3.capture2('curl', '-sL', '-o', tmp_path, url)
    return nil unless status.success? && File.exist?(tmp_path)

    size = File.size(tmp_path)
    { path: tmp_path, size: size }
  end

  def generate_signature(dmg_path)
    # Get private key from Keychain
    key, status = Open3.capture2(
      'security', 'find-generic-password', '-w',
      '-s', 'https://sparkle-project.org',
      '-a', 'EdDSA Private Key'
    )
    return nil unless status.success?

    key = key.strip

    # Use Swift to sign
    script = File.expand_path('sign_update.swift', __dir__)
    if File.exist?(script)
      sig, status = Open3.capture2('swift', script, dmg_path, key)
      return sig.strip if status.success?
    end

    # Fallback: inline Swift
    swift_code = <<~SWIFT
      import Foundation
      import CryptoKit
      let dmgData = FileManager.default.contents(atPath: CommandLine.arguments[1])!
      let keyData = Data(base64Encoded: CommandLine.arguments[2])!
      let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
      let sig = try! key.signature(for: dmgData)
      print(sig.base64EncodedString())
    SWIFT

    tmp_script = '/tmp/sign_sparkle.swift'
    File.write(tmp_script, swift_code)
    sig, status = Open3.capture2('swift', tmp_script, dmg_path, key)
    status.success? ? sig.strip : nil
  end

  def version_to_build(version)
    # 1.0.15 -> 1015
    parts = version.split('.')
    major = parts[0].to_i
    minor = parts[1].to_i
    patch = parts[2].to_i
    (major * 1000) + (minor * 100) + patch
  end

  def version_in_appcast?(version)
    return false unless File.exist?(APPCAST_PATH)
    content = File.read(APPCAST_PATH)
    content.include?("<title>#{version}</title>")
  end

  def generate_appcast_entry(version:, build:, size:, signature:, url:)
    date = DateTime.now.strftime('%a, %d %b %Y %H:%M:%S %z')
    description = get_changelog_description(version)

    <<~XML
        <item>
            <title>#{version}</title>
            <pubDate>#{date}</pubDate>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description>
                <![CDATA[
                #{description}
                ]]>
            </description>
            <enclosure url="#{url}"
                       sparkle:version="#{build}"
                       sparkle:shortVersionString="#{version}"
                       length="#{size}"
                       type="application/x-apple-diskimage"
                       sparkle:edSignature="#{signature}"/>
        </item>
    XML
  end

  def get_changelog_description(version)
    return "<p>See CHANGELOG.md for details</p>" unless File.exist?(CHANGELOG_PATH)

    content = File.read(CHANGELOG_PATH)

    # Extract section for this version
    pattern = /## \[#{Regexp.escape(version)}\].*?\n(.*?)(?=\n## \[|$)/m
    match = content.match(pattern)
    return "<p>See CHANGELOG.md for details</p>" unless match

    section = match[1].strip

    # Convert markdown to HTML
    html = section
      .gsub(/^### (.+)$/, '<h2>\1</h2>')
      .gsub(/^- \*\*(.+?)\*\*:?\s*(.*)$/, '<li><strong>\1</strong>: \2</li>')
      .gsub(/^- (.+)$/, '<li>\1</li>')

    # Wrap lists
    html = html.gsub(/(<li>.*?<\/li>\n?)+/) { |list| "<ul>\n#{list}</ul>" }

    html.strip
  end

  def update_appcast(new_entry)
    content = File.read(APPCAST_PATH)

    # Insert after <title>SaneBar Changelog</title>
    insertion_point = content.index("</title>\n") + "</title>\n".length

    updated = content.insert(insertion_point, new_entry)
    File.write(APPCAST_PATH, updated)
  end

  def error(msg)
    @errors << msg
    puts "❌ ERROR: #{msg}"
  end
end

# Parse arguments
version = nil
dry_run = false

ARGV.each_with_index do |arg, i|
  case arg
  when '--version', '-v'
    version = ARGV[i + 1]
  when '--dry-run', '-n'
    dry_run = true
  when '--help', '-h'
    puts <<~HELP
      Post-Release Script for SaneBar

      Updates appcast.xml after a GitHub release is created.

      Usage:
        #{$PROGRAM_NAME}                    # Auto-detect latest release
        #{$PROGRAM_NAME} --version 1.0.15   # Specific version
        #{$PROGRAM_NAME} --dry-run          # Preview without changes

      Options:
        --version, -v   Specify version (e.g., 1.0.15)
        --dry-run, -n   Preview changes without writing
        --help, -h      Show this help

      Requirements:
        - gh CLI installed and authenticated
        - Sparkle EdDSA Private Key in Keychain
    HELP
    exit 0
  end
end

success = PostRelease.new(version: version, dry_run: dry_run).run
exit(success ? 0 : 1)
