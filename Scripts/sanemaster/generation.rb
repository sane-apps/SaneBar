# frozen_string_literal: true

require_relative 'generation_templates'
require_relative 'generation_assets'
require_relative 'generation_mocks'

module SaneMasterModules
  # Code generation: tests, XcodeGen checks, API verification, documentation sync
  # Template, asset, and mock generation moved to dedicated modules
  module Generation
    include Base
    include GenerationTemplates
    include GenerationAssets
    include GenerationMocks

    def generate_test_file(args)
      puts '🧪 --- [ SANEMASTER TEST GENERATOR ] ---'

      if args.empty?
        print_test_generator_help
        return
      end

      test_name = args.shift
      options = parse_test_options(args)

      if options[:type] == 'ui'
        puts '⚠️  UI tests not yet implemented (SaneBarUITests directory does not exist)'
        puts '   Creating unit test instead...'
        options[:type] = 'unit'
      end

      test_dir = 'SaneBarTests'
      test_file = "#{test_dir}/#{test_name}.swift"

      if File.exist?(test_file)
        puts "⚠️  File already exists: #{test_file}"
        print 'Overwrite? (y/N): '
        return unless $stdin.gets.chomp.downcase == 'y'
      end

      content = generate_test_content(test_name, options)
      File.write(test_file, content)

      puts "✅ Created: #{test_file}"
      puts "\n📝 Next steps:"
      puts '  1. Review the generated test template'
      puts '  2. Add your test cases following AAA pattern (Arrange-Act-Assert)'
      puts '  3. Run: ./Scripts/SaneMaster.rb verify'
    end

    def check_xcodegen(files)
      return if files.empty?

      project_path = File.expand_path('SaneBar.xcodeproj', Dir.pwd)
      unless File.exist?(project_path)
        puts "❌ Project file not found. Run 'xcodegen generate' first."
        exit 1
      end

      begin
        require 'xcodeproj'
      rescue LoadError
        puts '⚠️  Skipping XcodeGen check (run with: bundle exec ./Scripts/SaneMaster.rb)'
        return
      end

      project_files = collect_project_files(project_path)
      missing_files = find_missing_files(files, project_files)

      if missing_files.any?
        puts '❌ New Swift files not in Xcode project:'
        missing_files.each { |f| puts "   - #{f}" }
        puts "\n💡 Run: xcodegen generate"
        exit 1
      end

      exit 0
    end

    def verify_api(args)
      if args.empty?
        print_verify_api_help
        return
      end

      api_name = args[0]
      framework = args[1] || 'auto'

      puts '🔍 --- [ SDK API VERIFICATION ] ---'
      puts "Searching for: #{api_name}"
      puts "Framework: #{framework == 'auto' ? 'auto-detect' : framework}"
      puts ''

      sdk_path, sdk_version = find_sdk
      return unless sdk_path

      puts "📦 Using SDK: #{sdk_version}"
      puts ''

      frameworks_to_search = framework == 'auto' ? default_frameworks : [framework]
      found = search_frameworks_for_api(sdk_path, frameworks_to_search, api_name)

      print_api_not_found(api_name) unless found
    end

    # rubocop:disable Naming/PredicateMethod
    def verify_documentation_sync
      # rubocop:enable Naming/PredicateMethod
      puts '📚 --- [ DOCUMENTATION SYNC CHECK ] ---'

      issues = []
      dev_doc = File.read('DEVELOPMENT.md')
      help_output = `./Scripts/SaneMaster.rb 2>&1`

      commands_in_help = help_output.scan(/^\s+(\w+)/).flatten.uniq
      commands_in_help.reject! { |c| %w[Examples: Commands: console check_xcodegen check_protocol_changes].include?(c) }

      commands_in_help.each do |cmd|
        issues << "Command '#{cmd}' exists in SaneMaster but not documented in DEVELOPMENT.md" unless dev_doc.include?(cmd) || dev_doc.include?("`#{cmd}`")
      end

      check_documentation_flags(dev_doc, issues)

      if issues.empty?
        puts '✅ Documentation is in sync with tools'
      else
        puts '⚠️  Documentation drift detected:'
        issues.each { |issue| puts "   - #{issue}" }
        puts "\n💡 Update DEVELOPMENT.md to reflect current tool capabilities"
      end

      issues.any?
    end

    private

    def print_test_generator_help
      puts 'Usage: ./Scripts/SaneMaster.rb gen_test <test_name> [options]'
      puts ''
      puts 'Options:'
      puts '  --type <unit|ui>     Test type (default: unit)'
      puts '  --framework <xctest|testing>  Framework (default: testing)'
      puts '  --target <class>     Target class/service to test'
      puts '  --async              Include async/await patterns'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature'
      puts '  ./Scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest'
    end

    def parse_test_options(args)
      options = { type: 'unit', framework: 'testing', target: nil, async: false }

      args.each_with_index do |arg, i|
        case arg
        when '--type' then options[:type] = args[i + 1] if args[i + 1]
        when '--framework' then options[:framework] = args[i + 1] if args[i + 1]
        when '--target' then options[:target] = args[i + 1] if args[i + 1]
        when '--async' then options[:async] = true
        end
      end

      options
    end

    def generate_test_content(test_name, options)
      if options[:framework] == 'xctest'
        generate_xctest_content(test_name, options)
      else
        generate_testing_framework_content(test_name, options)
      end
    end

    def generate_xctest_content(test_name, options)
      target_class = options[:target] || 'TargetClass'
      async_suffix = options[:async] ? ' async throws' : ''
      await_prefix = options[:async] ? 'await ' : ''
      timeout = options[:type] == 'ui' ? '300.0' : '60.0'
      timeout_comment = options[:type] == 'ui' ? '5 minutes' : '1 minute'

      <<~SWIFT
        //
        //  #{test_name}.swift
        //  #{options[:type] == 'ui' ? 'SaneBarUITests' : 'SaneBarTests'}
        //
        //  Generated by SaneMaster.rb test generator
        //  Follow AAA pattern: Arrange-Act-Assert
        //

        import XCTest
        #{'import XCUITest' if options[:type] == 'ui'}
        #{'import AVFoundation' if options[:async]}
        @testable import SaneBar

        @MainActor
        final class #{test_name}: XCTestCase {

            // MARK: - Test Setup

            var sut: #{target_class}!

            override func setUpWithError() throws {
                continueAfterFailure = false

                if #available(macOS 13.0, *) {
                    executionTimeAllowance = #{timeout} // #{timeout_comment} max per test
                }

                sut = #{target_class}()
            }

            override func tearDownWithError() throws {
                sut = nil
            }

            // MARK: - Test Cases

            func testInitialState()#{async_suffix} {
                // Arrange - (Setup is done in setUp)

                // Act
                // TODO: Replace with actual behavior verification

                // Assert
                XCTAssertNotNil(sut, "SUT should be initialized")
            }

            func testBasicFunctionality()#{async_suffix} {
                // Arrange
                let expectedValue = "expected"

                // Act
                #{await_prefix}let result = sut.someMethod()

                // Assert
                XCTAssertEqual(result, expectedValue, "Result should match expected value")
            }
        }
      SWIFT
    end

    def generate_testing_framework_content(test_name, options)
      target_class = options[:target] || 'TargetClass'
      async_suffix = options[:async] ? ' async throws' : ''
      await_prefix = options[:async] ? 'await ' : ''

      <<~SWIFT
        //
        //  #{test_name}.swift
        //  #{options[:type] == 'ui' ? 'SaneBarUITests' : 'SaneBarTests'}
        //
        //  Generated by SaneMaster.rb test generator
        //  Follow AAA pattern: Arrange-Act-Assert
        //

        import Testing
        #{'import AVFoundation' if options[:async]}
        @testable import SaneBar

        @Suite("#{test_name.gsub(/([A-Z])/, ' \\1').strip} Tests")
        @MainActor
        struct #{test_name} {

            var sut: #{target_class} { #{target_class}() }

            @Test("Initial state verification")
            func initialState()#{async_suffix} {
                let systemUnderTest = sut
                #expect(systemUnderTest != nil)
            }

            @Test("Basic functionality")
            func basicFunctionality()#{async_suffix} {
                let expectedValue = "expected"
                #{await_prefix}let result = sut.someMethod()
                #expect(result == expectedValue)
            }
        }
      SWIFT
    end

    def collect_project_files(project_path)
      require 'xcodeproj'
      project = Xcodeproj::Project.open(project_path)
      project_files = Set.new

      project.files.each do |file|
        next unless file.path&.end_with?('.swift')

        path = file.path
        project_files.add(path)
        project_files.add(path.sub(%r{^SaneBar/}, ''))
        project_files.add("SaneBar/#{path}") unless path.start_with?('SaneBar/')
      end

      project_files
    end

    def find_missing_files(files, project_files)
      missing = []
      files.each do |file|
        next unless file.end_with?('.swift')
        next if file.include?('Test')

        is_new = `git diff --cached --diff-filter=A --name-only -- "#{file}" 2>/dev/null`.strip == file
        next unless is_new

        normalized = file.start_with?('SaneBar/') ? file : "SaneBar/#{file}"
        path_without_prefix = file.sub(%r{^SaneBar/}, '')

        missing << file unless project_files.include?(file) || project_files.include?(normalized) || project_files.include?(path_without_prefix)
      end
      missing
    end

    def print_verify_api_help
      puts 'Usage: ./Scripts/SaneMaster.rb verify_api <APIName> [Framework]'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision'
      puts '  ./Scripts/SaneMaster.rb verify_api SCContentSharingPicker ScreenCaptureKit'
    end

    def find_sdk
      sdk_base = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs'
      sdks = Dir.glob("#{sdk_base}/MacOSX*.sdk").sort.reverse

      if sdks.empty?
        puts '❌ No macOS SDK found. Is Xcode installed?'
        return nil
      end

      sdk_path = sdks.first
      sdk_version = File.basename(sdk_path).gsub('MacOSX', '').gsub('.sdk', '')
      [sdk_path, sdk_version]
    end

    def default_frameworks
      %w[Vision AVFoundation ScreenCaptureKit Foundation AppKit SwiftUI CoreMedia]
    end

    def search_frameworks_for_api(sdk_path, frameworks, api_name)
      found = false
      frameworks.each do |fw|
        framework_path = "#{sdk_path}/System/Library/Frameworks/#{fw}.framework"
        next unless File.exist?(framework_path)

        swiftinterface_files = Dir.glob("#{framework_path}/**/*.swiftinterface")
        next if swiftinterface_files.empty?

        swiftinterface_files.each do |swift_file|
          result = `grep -n "#{api_name}" "#{swift_file}" 2>/dev/null`
          next if result.empty?

          found = true
          display_api_match(fw, swift_file, api_name, result)
        end
      end
      found
    end

    def display_api_match(framework, swift_file, api_name, result)
      puts "✅ Found in #{framework}:"
      puts "   File: #{File.basename(swift_file)}"
      puts ''

      lines = result.split("\n").first(3)
      lines.each do |line|
        line_num = line.split(':').first
        context = `sed -n '#{[line_num.to_i - 2, 1].max},#{line_num.to_i + 5}p' "#{swift_file}" 2>/dev/null`
        puts "   Line #{line_num}:"
        context.split("\n").each do |ctx_line|
          prefix = ctx_line.include?(api_name) ? '   >>> ' : '      '
          puts "#{prefix}#{ctx_line.strip}"
        end
        puts ''
      end
    end

    def print_api_not_found(api_name)
      puts "❌ API '#{api_name}' not found in SDK"
      puts ''
      puts '💡 Tips:'
      puts '   - Check spelling (case-sensitive)'
      puts '   - Try searching for partial name'
      puts '   - Framework may be different - try without framework to search all'
    end

    def check_documentation_flags(dev_doc, issues)
      issues << "DEVELOPMENT.md doesn't mention --ui flag for verify command" unless dev_doc.include?('verify --ui') || dev_doc.include?('--ui')
      issues << 'SDK API verification tool (verify_api) not documented' unless dev_doc.include?('verify_api') || dev_doc.include?('SDK API verification')
      return if dev_doc.include?('verify_mocks') || dev_doc.include?('mock synchronization')

      issues << 'Mock synchronization check (verify_mocks) not documented'
    end
  end
end
