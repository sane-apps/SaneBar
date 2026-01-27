#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate signed download URLs for crypto customers
# Usage: ./scripts/generate_download_link.rb [hours_valid]
#
# Examples:
#   ./scripts/generate_download_link.rb        # 48 hours (default)
#   ./scripts/generate_download_link.rb 24     # 24 hours
#   ./scripts/generate_download_link.rb 168    # 1 week

require 'openssl'

# Configuration
FILE_NAME = 'SaneBar-1.0.16.dmg'
BASE_URL = 'https://dist.sanebar.com'
DEFAULT_HOURS = 48

# Get secret from keychain
secret = `security find-generic-password -s sanebar-dist -a signing_secret -w 2>/dev/null`.strip
if secret.empty?
  warn "❌ Signing secret not found in keychain"
  warn "   Run: security add-generic-password -s sanebar-dist -a signing_secret -w 'YOUR_SECRET'"
  exit 1
end

# Calculate expiration
hours = (ARGV[0] || DEFAULT_HOURS).to_i
expires = (Time.now + (hours * 3600)).to_i

# Generate signature
message = "#{FILE_NAME}:#{expires}"
token = OpenSSL::HMAC.hexdigest('SHA256', secret, message)

# Build URL
signed_url = "#{BASE_URL}/#{FILE_NAME}?token=#{token}&expires=#{expires}"

# Output
puts
puts "🔗 Signed Download Link (valid for #{hours} hours)"
puts "=" * 60
puts signed_url
puts "=" * 60
puts
puts "Expires: #{Time.at(expires).strftime('%Y-%m-%d %H:%M:%S %Z')}"
puts

# Copy to clipboard
system("echo '#{signed_url}' | pbcopy")
puts "📋 Copied to clipboard!"
