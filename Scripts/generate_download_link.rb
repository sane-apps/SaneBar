#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate signed download URLs for SaneApps customers
# Canonical template: infra/SaneProcess/templates/scripts/generate_download_link.rb
#
# Usage: ./scripts/generate_download_link.rb [version] [hours_valid]
#
# Examples:
#   ./scripts/generate_download_link.rb              # Latest version, 48 hours
#   ./scripts/generate_download_link.rb 1.2          # Specific version, 48 hours
#   ./scripts/generate_download_link.rb 1.2 168      # Specific version, 1 week
#
# Reads app name and dist domain from .saneprocess in project root.

require 'openssl'
require 'yaml'

# Auto-detect from .saneprocess
PROJECT_ROOT = File.expand_path('..', __dir__)
config_path = File.join(PROJECT_ROOT, '.saneprocess')

unless File.exist?(config_path)
  warn "❌ No .saneprocess found in #{PROJECT_ROOT}"
  exit 1
end

config = YAML.safe_load(File.read(config_path))
app_name = config['name']
dist_host = config.dig('release', 'dist_host') || "dist.#{app_name.downcase}.com"
base_url = "https://#{dist_host}"

DEFAULT_HOURS = 48

# Get secret from keychain
secret = `security find-generic-password -s sanebar-dist -a signing_secret -w 2>/dev/null`.strip
if secret.empty?
  warn "❌ Signing secret not found in keychain"
  warn "   Run: security add-generic-password -s sanebar-dist -a signing_secret -w 'YOUR_SECRET'"
  exit 1
end

# Parse arguments
version = ARGV[0]
hours = (ARGV[1] || DEFAULT_HOURS).to_i

unless version
  warn "Usage: #{$PROGRAM_NAME} <version> [hours]"
  warn "  e.g. #{$PROGRAM_NAME} 1.0.5"
  exit 1
end

file_name = "#{app_name}-#{version}.dmg"

# Calculate expiration
expires = (Time.now + (hours * 3600)).to_i

# Generate signature
message = "#{file_name}:#{expires}"
token = OpenSSL::HMAC.hexdigest('SHA256', secret, message)

# Build URL
signed_url = "#{base_url}/#{file_name}?token=#{token}&expires=#{expires}"

# Output
puts
puts "Signed Download Link (valid for #{hours} hours)"
puts "=" * 70
puts signed_url
puts "=" * 70
puts
puts "App:     #{app_name} #{version}"
puts "Expires: #{Time.at(expires).strftime('%Y-%m-%d %H:%M:%S %Z')}"
puts

# Copy to clipboard
IO.popen('pbcopy', 'w') { |io| io.write(signed_url) }
puts "Copied to clipboard!"
