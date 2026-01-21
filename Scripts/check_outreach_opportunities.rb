#!/usr/bin/env ruby
# frozen_string_literal: true

# Check GitHub for outreach opportunities
# Run: ./scripts/check_outreach_opportunities.rb
# Or add to session start hook for automatic alerts

require 'net/http'
require 'json'
require 'time'

REPOS = {
  'jordanbaird/Ice' => {
    name: 'Ice',
    keywords: %w[alternative replacement switched macOS\ 26 Tahoe broken abandoned],
    min_age_days: 7  # Only issues older than 7 days
  },
  'dwarvesf/hidden' => {
    name: 'Hidden Bar',
    keywords: %w[alternative replacement broken macOS\ 26 macOS\ 15 not\ working],
    min_age_days: 3  # Abandoned project, faster response OK
  }
}.freeze

CACHE_FILE = File.expand_path('~/.cache/sanebar_outreach_seen.json')

def fetch_issues(repo, query)
  uri = URI("https://api.github.com/search/issues?q=repo:#{repo}+#{URI.encode_www_form_component(query)}+is:issue+is:open&sort=created&order=desc&per_page=10")

  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/vnd.github.v3+json'
  req['User-Agent'] = 'SaneBar-Outreach-Checker'

  # Use token if available
  token = ENV['GITHUB_TOKEN']
  req['Authorization'] = "Bearer #{token}" if token

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  return [] unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(res.body)['items'] || []
rescue StandardError => e
  warn "Error fetching #{repo}: #{e.message}"
  []
end

def load_seen
  return {} unless File.exist?(CACHE_FILE)
  JSON.parse(File.read(CACHE_FILE))
rescue StandardError
  {}
end

def save_seen(seen)
  dir = File.dirname(CACHE_FILE)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  File.write(CACHE_FILE, JSON.pretty_generate(seen))
end

def format_issue(issue, repo_name)
  age_days = ((Time.now - Time.parse(issue['created_at'])) / 86400).to_i
  reactions = issue.dig('reactions', 'total_count') || 0
  comments = issue['comments'] || 0

  <<~ISSUE
    [#{repo_name}] #{issue['title']}
    #{issue['html_url']}
    Age: #{age_days} days | Reactions: #{reactions} | Comments: #{comments}
  ISSUE
end

def main
  seen = load_seen
  new_opportunities = []

  REPOS.each do |repo, config|
    config[:keywords].each do |keyword|
      issues = fetch_issues(repo, keyword)

      issues.each do |issue|
        # Skip if already seen
        next if seen[issue['html_url']]

        # Skip if too new
        age_days = ((Time.now - Time.parse(issue['created_at'])) / 86400).to_i
        next if age_days < config[:min_age_days]

        # Skip if maintainer recently responded (check last comment)
        # This is a heuristic - if issue has 0 comments and is old, it's abandoned

        new_opportunities << {
          issue: issue,
          repo_name: config[:name],
          keyword: keyword
        }

        # Mark as seen
        seen[issue['html_url']] = Time.now.iso8601
      end
    end

    sleep 0.5  # Rate limiting
  end

  save_seen(seen)

  if new_opportunities.empty?
    puts "No new outreach opportunities found."
    return
  end

  puts "=" * 60
  puts "NEW OUTREACH OPPORTUNITIES (#{new_opportunities.size} found)"
  puts "=" * 60
  puts

  # Group by repo
  by_repo = new_opportunities.group_by { |o| o[:repo_name] }

  by_repo.each do |repo_name, opps|
    puts "## #{repo_name}"
    puts
    opps.each do |opp|
      puts format_issue(opp[:issue], repo_name)
      puts "  Matched keyword: \"#{opp[:keyword]}\""
      puts
    end
  end

  puts "=" * 60
  puts "Review guidelines: marketing/GITHUB_OUTREACH.md"
  puts "=" * 60
end

main if __FILE__ == $PROGRAM_NAME
