#!/usr/bin/env ruby
# frozen_string_literal: true

# Deep analyze Lemon Squeezy sales patterns
# Usage: ./scripts/deep_analyze_sales.rb

require 'net/http'
require 'json'
require 'uri'
require 'date'

# Configuration
API_URL = 'https://api.lemonsqueezy.com/v1/orders'
KEYCHAIN_SERVICE = 'lemonsqueezy'
KEYCHAIN_ACCOUNT = 'api_key'

# Known public email domains to filter out
PUBLIC_DOMAINS = %w[
  gmail.com yahoo.com hotmail.com outlook.com icloud.com me.com live.com
  aol.com protonmail.com proton.me zoho.com mail.com gmx.com yandex.com
  duck.com pm.me
].freeze

def get_api_key
  key = `security find-generic-password -s #{KEYCHAIN_SERVICE} -a #{KEYCHAIN_ACCOUNT} -w 2>/dev/null`.strip
  if key.empty?
    puts "❌ API key not found in keychain"
    exit 1
  end
  key
end

def fetch_orders(api_key)
  orders = []
  page = 1
  loop do
    # Only fetch needed fields if possible, but standard endpoint is fine
    uri = URI("#{API_URL}?page[number]=#{page}&page[size]=100&sort=-createdAt")
    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/vnd.api+json'
    request['Content-Type'] = 'application/vnd.api+json'
    request['Authorization'] = "Bearer #{api_key}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      puts "❌ Failed to fetch page #{page}: #{response.message}"
      break
    end

    json = JSON.parse(response.body)
    data = json['data']
    break if data.nil? || data.empty?

    orders.concat(data)
    
    meta = json['meta']
    last_page = meta.dig('page', 'lastPage')
    
    print "\rBound #{orders.count} orders..."
    
    break if page >= last_page
    page += 1
  end
  puts "\n✅ Fetched #{orders.count} total orders"
  orders
end

def infer_location(currency)
  # Basic mapping from currency to likely region if country code is missing
  case currency
  when 'USD' then 'United States (Likely)'
  when 'EUR' then 'Europe'
  when 'GBP' then 'United Kingdom'
  when 'CAD' then 'Canada'
  when 'AUD' then 'Australia'
  when 'JPY' then 'Japan'
  when 'INR' then 'India'
  else currency
  end
end

def analyze_orders(orders)
  total_revenue_cents = 0
  sales_by_country = Hash.new(0)
  sales_by_currency = Hash.new(0)
  sales_by_domain_type = Hash.new(0)
  corporate_domains = []
  
  orders.each do |order|
    attrs = order['attributes']
    next unless attrs['status'] == 'paid'

    total_revenue_cents += attrs['total']
    
    # 1. Location Analysis
    # Since billing address isn't in top-level attributes, we use currency as proxy for now
    # If we really need country, we'd need to fetch customer relationships, which is N+1 queries.
    # We'll stick to currency for this rapid check.
    currency = attrs['currency']
    sales_by_currency[currency] += 1
    
    # 2. Email Analysis
    email = attrs['user_email']
    if email
      domain = email.split('@').last.downcase
      if PUBLIC_DOMAINS.include?(domain)
        sales_by_domain_type['Personal (Gmail, iCloud, etc)'] += 1
      else
        sales_by_domain_type['Corporate / Custom Domain'] += 1
        corporate_domains << domain unless corporate_domains.include?(domain)
      end
    end
  end

  puts "\n🌍 Sales Geography (by Currency)"
  puts "================================'"
  sales_by_currency.sort_by { |_, v| -v }.each do |currency, count|
    puts "  #{currency} (#{infer_location(currency)}): #{count}"
  end

  puts "\n👥 Buyer Persona (by Email Domain)"
  puts "=================================="
  sales_by_domain_type.sort_by { |_, v| -v }.each do |type, count|
    puts "  #{type}: #{count}"
  end
  
  puts "\n🏢 Notable Company/Custom Domains (Potential B2B Leads)"
  puts "-----------------------------------------------------"
  if corporate_domains.any?
    puts corporate_domains.take(15).map { |d| "  - #{d}" }.join("\n")
    puts "  ...and #{corporate_domains.count - 15} more" if corporate_domains.count > 15
  else
    puts "  (None detected)"
  end
  
  puts "\n💰 Total Revenue: $#{(total_revenue_cents / 100.0).round(2)}"
end

api_key = get_api_key
orders = fetch_orders(api_key)
analyze_orders(orders)
