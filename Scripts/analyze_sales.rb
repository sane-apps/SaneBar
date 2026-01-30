#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze Lemon Squeezy sales patterns
# Usage: ./scripts/analyze_sales.rb

require 'net/http'
require 'json'
require 'uri'
require 'date'

# Configuration
API_URL = 'https://api.lemonsqueezy.com/v1/orders'
KEYCHAIN_SERVICE = 'lemonsqueezy'
KEYCHAIN_ACCOUNT = 'api_key'

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

def analyze_orders(orders)
  total_revenue_cents = 0
  sales_by_date = Hash.new(0)
  sales_by_country = Hash.new(0)
  sales_by_hour = Hash.new(0)
  
  orders.each do |order|
    attrs = order['attributes']
    next unless attrs['status'] == 'paid'

    total_revenue_cents += attrs['total']
    
    date = DateTime.parse(attrs['created_at'])
    day_key = date.strftime('%Y-%m-%d')
    hour_key = date.hour
    
    sales_by_date[day_key] += 1
    sales_by_hour[hour_key] += 1
    
    # Billing address might be nested or direct depending on API version, 
    # checking structure from previous output implies strictly attributes for some fields,
    # but country isn't top level in attributes usually? 
    # Actually previous output didn't show billing_address in attributes top level?
    # Wait, previous curl output had: "user_email", "total", etc.
    # Let's checking for user location if available, otherwise skip.
    # Looking at docs/previous output: attributes -> "user_email", "total", "created_at"
    # It seems location data might be sparse or in relationships, but let's try just date/time first.
  end

  puts "\n📊 Sales Analysis"
  puts "================="
  puts "Total Orders: #{orders.count}"
  puts "Total Revenue: $#{(total_revenue_cents / 100.0).round(2)}"
  
  puts "\n📅 Daily Trend (Last 7 active days):"
  sales_by_date.sort.reverse.take(7).each do |date, count|
    puts "  #{date}: #{count} sales"
  end

  puts "\npw Hourly Distribution (UTC):"
  sales_by_hour.sort.each do |hour, count|
    bar = "█" * count
    puts "  #{'%02d' % hour}:00 : #{count} #{bar}"
  end
end

api_key = get_api_key
orders = fetch_orders(api_key)
analyze_orders(orders)
