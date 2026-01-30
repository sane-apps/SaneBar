#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze Lemon Squeezy sales by product
# Usage: ./scripts/analyze_sales_by_product.rb

require 'net/http'
require 'json'
require 'uri'

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

def analyze_by_product(orders)
  product_stats = Hash.new { |h, k| h[k] = { count: 0, revenue_cents: 0 } }
  
  orders.each do |order|
    attrs = order['attributes']
    next unless attrs['status'] == 'paid'

    item = attrs['first_order_item']
    next unless item

    product_name = item['product_name']
    variant_name = item['variant_name']
    key = "#{product_name} (#{variant_name})"
    
    product_stats[key][:count] += 1
    # Use order total to account for any potential discounts applied to the order, 
    # or item price if we want strict product value. 
    # Usually strictly item price * quantity is better for product analysis, 
    # but 'total' reflects actual cash collected.
    # Let's use the item subtotal (price * quantity) to see product performance, 
    # but the prompt asked for "sales" which usually implies revenue.
    # We will use the order total for simplicity assuming single-item orders which is typical for this app.
    product_stats[key][:revenue_cents] += attrs['total']
  end

  puts "\n📦 Sales by Product"
  puts "==================="
  puts sprintf("%-40s | %-10s | %s", "Product (Variant)", "Sales", "Revenue")
  puts "-" * 65

  product_stats.sort_by { |_, v| -v[:revenue_cents] }.each do |name, stats|
    revenue = (stats[:revenue_cents] / 100.0).round(2)
    puts sprintf("%-40s | %-10d | $%.2f", name, stats[:count], revenue)
  end
  puts "-" * 65
  total_rev = product_stats.values.sum { |s| s[:revenue_cents] } / 100.0
  puts sprintf("%-40s | %-10d | $%.2f", "TOTAL", product_stats.values.sum { |s| s[:count] }, total_rev)
end

api_key = get_api_key
orders = fetch_orders(api_key)
analyze_by_product(orders)
