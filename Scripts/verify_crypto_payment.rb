#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify crypto payment and send download link
# Usage: ./scripts/verify_crypto_payment.rb <tx_hash> <customer_email>
#
# Automatically detects crypto type from tx hash format:
#   - BTC: 64 hex chars
#   - SOL: Base58, typically 88 chars
#   - ZEC: 64 hex chars (checks ZEC explorer)

require 'net/http'
require 'json'
require 'uri'
require 'openssl'

# === Configuration ===
WALLETS = {
  btc: '3Go9nJu3dj2qaa4EAYXrTsTf5AnhcrPQke',
  sol: 'FBvU83GUmwEYk3HMwZh3GBorGvrVVWSPb8VLCKeLiWZZ',
  zec: 't1PaQ7LSoRDVvXLaQTWmy5tKUAiKxuE9hBN'
}.freeze

MIN_USD_VALUE = 4.50  # Allow slight variance for fees

# === Helpers ===
def fetch_json(url)
  uri = URI(url)
  response = Net::HTTP.get_response(uri)
  return nil unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
rescue StandardError => e
  warn "API error: #{e.message}"
  nil
end

def get_btc_price
  data = fetch_json('https://api.coinbase.com/v2/prices/BTC-USD/spot')
  data&.dig('data', 'amount')&.to_f || 43000.0  # Fallback
end

def get_sol_price
  data = fetch_json('https://api.coinbase.com/v2/prices/SOL-USD/spot')
  data&.dig('data', 'amount')&.to_f || 100.0  # Fallback
end

def get_zec_price
  data = fetch_json('https://api.coinbase.com/v2/prices/ZEC-USD/spot')
  data&.dig('data', 'amount')&.to_f || 30.0  # Fallback
end

# === Blockchain Verification ===
def verify_btc(tx_hash)
  # Use Blockstream API (free, no key)
  data = fetch_json("https://blockstream.info/api/tx/#{tx_hash}")
  return { valid: false, error: 'Transaction not found' } unless data

  # Check if any output goes to our wallet
  our_output = data['vout']&.find { |out| out.dig('scriptpubkey_address') == WALLETS[:btc] }
  return { valid: false, error: 'Payment not sent to our wallet' } unless our_output

  # Calculate USD value
  satoshis = our_output['value']
  btc_amount = satoshis / 100_000_000.0
  btc_price = get_btc_price
  usd_value = btc_amount * btc_price

  # Check confirmations
  confirmations = data['status']['confirmed'] ? (data['status']['block_height'] ? 1 : 0) : 0

  {
    valid: usd_value >= MIN_USD_VALUE,
    crypto: 'BTC',
    amount: btc_amount,
    usd_value: usd_value.round(2),
    confirmations: confirmations,
    error: usd_value < MIN_USD_VALUE ? "Payment too small: $#{usd_value.round(2)}" : nil
  }
end

def verify_sol(tx_hash)
  # Use Solana public RPC
  uri = URI('https://api.mainnet-beta.solana.com')
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = {
    jsonrpc: '2.0',
    id: 1,
    method: 'getTransaction',
    params: [tx_hash, { encoding: 'jsonParsed', maxSupportedTransactionVersion: 0 }]
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  data = JSON.parse(response.body)
  tx = data['result']
  return { valid: false, error: 'Transaction not found' } unless tx

  # Look for transfer to our wallet
  instructions = tx.dig('transaction', 'message', 'instructions') || []
  post_balances = tx.dig('meta', 'postBalances') || []
  pre_balances = tx.dig('meta', 'preBalances') || []
  accounts = tx.dig('transaction', 'message', 'accountKeys') || []

  # Find our wallet in the accounts
  our_index = accounts.index { |acc| (acc.is_a?(Hash) ? acc['pubkey'] : acc) == WALLETS[:sol] }

  if our_index
    lamports_received = (post_balances[our_index] || 0) - (pre_balances[our_index] || 0)
    sol_amount = lamports_received / 1_000_000_000.0
    sol_price = get_sol_price
    usd_value = sol_amount * sol_price

    return {
      valid: usd_value >= MIN_USD_VALUE && lamports_received > 0,
      crypto: 'SOL',
      amount: sol_amount.round(6),
      usd_value: usd_value.round(2),
      confirmations: tx.dig('slot') ? 1 : 0,
      error: usd_value < MIN_USD_VALUE ? "Payment too small: $#{usd_value.round(2)}" : nil
    }
  end

  { valid: false, error: 'Payment not sent to our wallet' }
rescue StandardError => e
  { valid: false, error: "SOL verification error: #{e.message}" }
end

def verify_zec(tx_hash)
  # Use zcha.in API
  data = fetch_json("https://api.zcha.in/v2/mainnet/transactions/#{tx_hash}")
  return { valid: false, error: 'Transaction not found' } unless data

  # Check outputs for our wallet
  our_output = data['vout']&.find { |out| out['scriptPubKey']&.dig('addresses')&.include?(WALLETS[:zec]) }
  return { valid: false, error: 'Payment not sent to our wallet' } unless our_output

  zec_amount = our_output['value'].to_f
  zec_price = get_zec_price
  usd_value = zec_amount * zec_price

  {
    valid: usd_value >= MIN_USD_VALUE,
    crypto: 'ZEC',
    amount: zec_amount,
    usd_value: usd_value.round(2),
    confirmations: data['confirmations'] || 0,
    error: usd_value < MIN_USD_VALUE ? "Payment too small: $#{usd_value.round(2)}" : nil
  }
rescue StandardError => e
  { valid: false, error: "ZEC verification error: #{e.message}" }
end

def detect_and_verify(tx_hash)
  tx_hash = tx_hash.strip

  # SOL uses Base58, typically 88 chars, contains non-hex chars
  if tx_hash.length > 70 && tx_hash.match?(/[^0-9a-fA-F]/)
    return verify_sol(tx_hash)
  end

  # BTC and ZEC both use 64-char hex
  if tx_hash.length == 64 && tx_hash.match?(/^[0-9a-fA-F]+$/)
    # Try BTC first
    result = verify_btc(tx_hash)
    return result if result[:valid] || result[:error] != 'Transaction not found'

    # Try ZEC
    result = verify_zec(tx_hash)
    return result if result[:valid] || result[:error] != 'Transaction not found'

    return { valid: false, error: 'Transaction not found on BTC or ZEC networks' }
  end

  { valid: false, error: 'Invalid transaction hash format' }
end

# === Download Link Generation ===
def generate_signed_url
  signing_secret = `security find-generic-password -s sanebar-dist -a signing_secret -w 2>/dev/null`.strip
  return nil if signing_secret.empty?

  file_name = 'SaneBar-1.0.16.dmg'
  expires = (Time.now + 48 * 3600).to_i
  message = "#{file_name}:#{expires}"
  token = OpenSSL::HMAC.hexdigest('SHA256', signing_secret, message)

  "https://dist.sanebar.com/#{file_name}?token=#{token}&expires=#{expires}"
end

# === Email Sending ===
def send_download_email(customer_email, crypto_type, amount, usd_value)
  resend_key = `security find-generic-password -s resend -a api_key -w 2>/dev/null`.strip
  return { success: false, error: 'Resend API key not found' } if resend_key.empty?

  download_url = generate_signed_url
  return { success: false, error: 'Could not generate download URL' } unless download_url

  html_body = <<~HTML
    <div style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px;">
      <h2 style="color: #1a1a2e;">Payment Verified! ✓</h2>
      <p>We received your #{crypto_type} payment of <strong>#{amount} #{crypto_type}</strong> (~$#{usd_value} USD).</p>
      <p>Your SaneBar download is ready:</p>
      <div style="text-align: center; margin: 30px 0;">
        <a href="#{download_url}" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 14px 28px; border-radius: 8px; text-decoration: none; font-weight: 600; display: inline-block;">Download SaneBar</a>
      </div>
      <p style="color: #666; font-size: 14px;">This link expires in 48 hours. If you need a new link, just reply to this email.</p>
      <p style="color: #666; font-size: 14px;">Need help? Check out the <a href="https://github.com/sane-apps/SaneBar">documentation</a> or reply to this email.</p>
      <p style="margin-top: 30px;">Cheers,<br><strong>Mr. Sane</strong></p>
    </div>
  HTML

  uri = URI('https://api.resend.com/emails')
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{resend_key}"
  request['Content-Type'] = 'application/json'
  request.body = {
    from: 'Mr. Sane <hi@saneapps.com>',
    to: customer_email,
    subject: 'Your SaneBar Download is Ready!',
    html: html_body
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  result = JSON.parse(response.body)
  if result['id']
    { success: true, email_id: result['id'] }
  else
    { success: false, error: result['message'] || 'Unknown error' }
  end
rescue StandardError => e
  { success: false, error: e.message }
end

# === Main ===
if ARGV.length < 2
  puts "Usage: #{$PROGRAM_NAME} <tx_hash> <customer_email>"
  puts ""
  puts "Example:"
  puts "  #{$PROGRAM_NAME} abc123def456... customer@example.com"
  exit 1
end

tx_hash = ARGV[0]
customer_email = ARGV[1]

puts "🔍 Verifying transaction: #{tx_hash[0..20]}..."
puts ""

result = detect_and_verify(tx_hash)

if result[:valid]
  puts "✅ Payment verified!"
  puts "   Crypto: #{result[:crypto]}"
  puts "   Amount: #{result[:amount]} #{result[:crypto]}"
  puts "   Value:  $#{result[:usd_value]} USD"
  puts "   Confirmations: #{result[:confirmations]}"
  puts ""
  puts "📧 Sending download link to #{customer_email}..."

  email_result = send_download_email(customer_email, result[:crypto], result[:amount], result[:usd_value])

  if email_result[:success]
    puts "✅ Email sent successfully!"
    puts "   Email ID: #{email_result[:email_id]}"
  else
    puts "❌ Email failed: #{email_result[:error]}"
    exit 1
  end
else
  puts "❌ Payment verification failed"
  puts "   Error: #{result[:error]}"
  exit 1
end
