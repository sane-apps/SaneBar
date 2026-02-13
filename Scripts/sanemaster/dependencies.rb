# frozen_string_literal: true

module SaneMasterModules
  # Version checking, dependency graphs, CI parity, MCP verification
  module Dependencies
    include Base

    def check_latest_versions(args)
      puts '🔍 --- [ SANEMASTER VERSION CHECK ] ---'
      force_refresh = args.include?('--refresh') || args.include?('-f')

      cache = load_version_cache(force_refresh: force_refresh)

      if cache[:fetched_at]
        age_days = ((Time.now - Time.parse(cache[:fetched_at])) / 86_400).round(1)
        puts "📅 Cache age: #{age_days} days #{'(refreshed)' if force_refresh}"
        puts ''
      end

      puts 'Tool            Installed    Latest       Status'
      puts '-' * 55

      all_current = true
      TOOL_SOURCES.each_key do |tool|
        installed = get_installed_version(tool)
        latest = cache[:versions][tool] || 'unknown'

        status = determine_version_status(installed, latest)
        all_current = false if status.include?('missing') || status.include?('update')

        puts format('%-15<tool>s %-12<installed>s %-12<latest>s %<status>s',
                    tool: tool, installed: installed, latest: latest, status: status)
      end

      puts ''
      if all_current
        puts '✅ All tools are up to date!'
      else
        puts '💡 Run `brew upgrade <tool>` or `./Scripts/SaneMaster.rb bootstrap` to update'
      end

      puts "\n🔄 To refresh cache: ./Scripts/SaneMaster.rb versions --refresh"
    end

    def load_version_cache(force_refresh: false)
      ensure_sop_dirs

      if !force_refresh && File.exist?(VERSION_CACHE_FILE)
        begin
          cache = JSON.parse(File.read(VERSION_CACHE_FILE), symbolize_names: true)
          cache_age = Time.now - Time.parse(cache[:fetched_at])
          return cache if cache_age < VERSION_CACHE_MAX_AGE
        rescue StandardError
          # Cache corrupted, will refresh
        end
      end

      puts '🌐 Fetching latest versions from package managers...'
      versions = {}

      TOOL_SOURCES.each do |tool, config|
        print "   #{tool}... "
        version = fetch_latest_version(config)
        versions[tool] = version
        puts version
      end

      cache = { fetched_at: Time.now.iso8601, versions: versions }
      File.write(VERSION_CACHE_FILE, JSON.pretty_generate(cache))
      puts ''
      cache
    end

    def fetch_latest_version(config)
      case config[:type]
      when :homebrew then fetch_homebrew_version(config[:formula])
      when :github then fetch_github_version(config[:repo])
      when :rubygems then fetch_rubygems_version(config[:gem])
      else 'unknown'
      end
    rescue StandardError
      'unknown'
    end

    def get_installed_version(tool)
      case tool
      when 'swiftlint'
        `swiftlint --version 2>/dev/null`.strip.split.first || 'not installed'
      when 'xcodegen'
        output = `xcodegen --version 2>/dev/null`
        output.match(/Version: ([\d.]+)/)&.[](1) || 'not installed'
      when 'periphery'
        `periphery version 2>/dev/null`.strip || 'not installed'
      when 'mockolo'
        `mockolo --version 2>/dev/null`.strip || 'not installed'
      when 'lefthook'
        output = `lefthook --version 2>/dev/null`
        output.match(/lefthook version ([\d.]+)/)&.[](1) || 'not installed'
      when 'fastlane'
        output = `#{HOMEBREW_BUNDLE} exec fastlane --version 2>/dev/null`
        output.match(/fastlane ([\d.]+)/)&.[](1) || 'not installed'
      when 'ruby'
        output = `#{HOMEBREW_RUBY} --version 2>/dev/null`
        output.match(/ruby ([\d.]+)/)&.[](1) || 'not installed'
      else
        'unknown'
      end
    rescue StandardError
      'not installed'
    end

    def show_dependency_graph(args)
      puts '📊 --- [ SANEMASTER DEPENDENCY GRAPH ] ---'

      output_format = args.include?('--dot') ? :dot : :ascii

      deps = {
        swift_packages: scan_swift_packages,
        ruby_gems: scan_ruby_gems,
        homebrew: scan_homebrew_deps,
        frameworks: scan_frameworks
      }

      if output_format == :dot
        generate_dot_graph(deps)
      else
        print_ascii_graph(deps)
      end
    end

    def verify_mcps
      puts '🔍 --- [ MCP VERIFICATION ] ---'
      puts ''

      sop_mcps = {
        'apple-docs' => { package: '@mweinbach/apple-docs-mcp@latest', required: true },
        'github' => { package: '@modelcontextprotocol/server-github', required: true },
        'context7' => { package: '@upstash/context7-mcp@latest', required: true },
        'macos-automator' => { package: '@steipete/macos-automator-mcp', required: true }
      }

      config_paths = ['.mcp.json', '.cursor/mcp.json']
      all_valid = true

      config_paths.each do |config_path|
        next unless File.exist?(config_path)

        all_valid = check_mcp_config_file(config_path, sop_mcps, all_valid)
      end

      unless File.exist?('.cursor/mcp.json')
        puts '⚠️  .cursor/mcp.json not found (Cursor may use this location)'
        puts '   Run: cp .mcp.json .cursor/mcp.json'
        all_valid = false
      end

      print_mcp_verification_summary(all_valid)
    end

    private

    def determine_version_status(installed, latest)
      if installed == 'not installed'
        '❌ missing'
      elsif latest == 'unknown'
        '❓ unknown'
      elsif Gem::Version.new(installed.gsub(/[^\d.]/, '')) >= Gem::Version.new(latest.gsub(/[^\d.]/, ''))
        '✅ current'
      else
        '⬆️  update available'
      end
    end

    def fetch_homebrew_version(formula)
      output = `brew info #{formula} 2>/dev/null`.lines.first
      version = output&.match(/stable ([\d.]+)/)&.[](1) ||
                output&.match(/#{formula}[:\s]+([\d.]+)/)&.[](1)
      return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

      version || 'unknown'
    end

    def fetch_github_version(repo)
      output = `curl -s "https://api.github.com/repos/#{repo}/releases" 2>/dev/null`
      releases = JSON.parse(output)
      stable = releases.find { |r| !r['prerelease'] && !r['draft'] }
      version = stable&.dig('tag_name')&.gsub(/^v/, '')
      return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

      version || 'unknown'
    rescue StandardError
      'unknown'
    end

    def fetch_rubygems_version(gem_name)
      output = `gem search ^#{gem_name}$ --remote 2>/dev/null`
      version = output&.match(/#{gem_name} \(([\d.]+)\)/)&.[](1)
      return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

      version || 'unknown'
    end

    def scan_swift_packages
      package_file = 'SaneBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
      package_file = 'Package.resolved' unless File.exist?(package_file)
      return [] unless File.exist?(package_file)

      data = JSON.parse(File.read(package_file))
      pins = data['pins'] || data.dig('object', 'pins') || []
      pins.map do |pin|
        {
          name: pin['identity'] || pin['package'],
          version: pin.dig('state', 'version') || pin.dig('state', 'revision')&.[](0..6) || 'branch',
          url: pin['location'] || pin['repositoryURL']
        }
      end
    rescue StandardError
      []
    end

    def scan_ruby_gems
      return [] unless File.exist?('Gemfile.lock')

      gems = []
      in_specs = false

      File.readlines('Gemfile.lock').each do |line|
        stripped = line.strip
        if stripped == 'specs:'
          in_specs = true
        elsif in_specs && line.match(/^\s{4}(\S+)\s+\(([\d.]+)\)/)
          gems << { name: ::Regexp.last_match(1), version: ::Regexp.last_match(2) }
        elsif stripped == 'GEM' || stripped.empty? || line.start_with?('PLATFORMS')
          in_specs = false
        end
      end

      gems.first(15)
    end

    def scan_homebrew_deps
      TOOL_SOURCES.keys.filter_map do |tool|
        version = get_installed_version(tool)
        { name: tool, version: version } if version != 'not installed'
      end
    end

    def scan_frameworks
      frameworks = Set.new
      Dir.glob('SaneBar/**/*.swift').each do |file|
        File.readlines(file).each do |line|
          if line.match(/^import\s+(\w+)/)
            fw = ::Regexp.last_match(1)
            frameworks << fw unless %w[Foundation SwiftUI Combine].include?(fw)
          end
        end
      rescue StandardError
        next
      end
      frameworks.to_a.sort.map { |f| { name: f, version: 'system' } }
    end

    def print_ascii_graph(deps)
      puts ''
      puts '┌─────────────────────────────────────────────────────────┐'
      puts '│                    SaneBar                            │'
      puts '└─────────────────────────────────────────────────────────┘'
      puts '                           │'

      print_package_section('Swift Packages', deps[:swift_packages])
      print_gem_section(deps[:ruby_gems])
      print_tool_section(deps[:homebrew])
      print_framework_section(deps[:frameworks])

      puts ''
      puts "📊 Total: #{deps[:swift_packages].count} Swift packages, #{deps[:ruby_gems].count} gems, " \
           "#{deps[:homebrew].count} tools, #{deps[:frameworks].count} frameworks"
    end

    def print_package_section(title, packages)
      return unless packages.any?

      puts '          ┌────────────────┴────────────────┐'
      puts "          │        #{title.ljust(24)}│"
      puts '          └─────────────────────────────────┘'
      packages.each { |pkg| puts "                    ├── #{pkg[:name]} (#{pkg[:version]})" }
      puts ''
    end

    def print_gem_section(gems)
      return unless gems.any?

      puts '          ┌─────────────────────────────────┐'
      puts '          │          Ruby Gems              │'
      puts '          └─────────────────────────────────┘'
      gems.first(10).each { |gem| puts "                    ├── #{gem[:name]} (#{gem[:version]})" }
      puts "                    └── ... and #{gems.count - 10} more" if gems.count > 10
      puts ''
    end

    def print_tool_section(tools)
      return unless tools.any?

      puts '          ┌─────────────────────────────────┐'
      puts '          │        Homebrew Tools           │'
      puts '          └─────────────────────────────────┘'
      tools.each { |tool| puts "                    ├── #{tool[:name]} (#{tool[:version]})" }
      puts ''
    end

    def print_framework_section(frameworks)
      return unless frameworks.any?

      puts '          ┌─────────────────────────────────┐'
      puts '          │       Apple Frameworks          │'
      puts '          └─────────────────────────────────┘'
      frameworks.first(15).each { |fw| puts "                    ├── #{fw[:name]}" }
      puts "                    └── ... and #{frameworks.count - 15} more" if frameworks.count > 15
    end

    def generate_dot_graph(deps)
      dot_file = 'dependencies.dot'
      File.open(dot_file, 'w') do |f|
        f.puts 'digraph Dependencies {'
        f.puts '  rankdir=TB;'
        f.puts '  node [shape=box];'
        f.puts ''
        f.puts '  SaneBar [style=filled, fillcolor=lightblue];'
        f.puts ''

        deps[:swift_packages].each do |pkg|
          f.puts "  \"#{pkg[:name]}\" [label=\"#{pkg[:name]}\\n#{pkg[:version]}\"];"
          f.puts "  SaneBar -> \"#{pkg[:name]}\";"
        end

        deps[:homebrew].each do |tool|
          f.puts "  \"#{tool[:name]}\" [label=\"#{tool[:name]}\\n#{tool[:version]}\", style=filled, fillcolor=lightyellow];"
          f.puts "  SaneBar -> \"#{tool[:name]}\" [style=dashed];"
        end

        f.puts '}'
      end

      puts "✅ Generated: #{dot_file}"
      puts '💡 View with: dot -Tpng dependencies.dot -o dependencies.png && open dependencies.png'
    end

    def check_mcp_config_file(config_path, sop_mcps, all_valid)
      puts "📄 Checking: #{config_path}"
      config = JSON.parse(File.read(config_path))
      servers = config['mcpServers'] || {}

      sop_mcps.each do |name, info|
        if servers.key?(name)
          package = servers[name]['args']&.last || 'unknown'
          puts "   ✅ #{name}: Configured (#{package})"
        else
          puts "   ❌ #{name}: MISSING"
          all_valid = false if info[:required]
        end
      end

      extra = servers.keys - sop_mcps.keys
      puts "   📦 Extra servers: #{extra.join(', ')}" if extra.any?
      puts "   📊 Total: #{servers.length} servers"
      puts ''
      all_valid
    rescue JSON::ParserError => e
      puts "   ❌ Invalid JSON: #{e.message}"
      puts ''
      false
    end

    def print_mcp_verification_summary(all_valid)
      puts ''
      if all_valid
        puts '✅ All required MCPs are configured'
        puts ''
        puts '💡 To verify MCPs are working in Cursor:'
        puts '   1. Restart Cursor'
        puts '   2. Check Settings > MCP Tools'
      else
        puts '❌ Some required MCPs are missing or misconfigured'
        puts ''
        puts '💡 Fix by:'
        puts '   1. Add missing MCPs to .mcp.json'
        puts '   2. Copy to .cursor/mcp.json: cp .mcp.json .cursor/mcp.json'
        puts '   3. Restart Cursor'
      end
    end
  end
end
