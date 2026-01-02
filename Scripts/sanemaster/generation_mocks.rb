# frozen_string_literal: true

module SaneMasterModules
  # Mock generation using Mockolo
  module GenerationMocks
    include Base

    def generate_mocks(args)
      puts '🎭 --- [ SANEMASTER MOCK GENERATOR ] ---'

      unless system('which mockolo > /dev/null 2>&1')
        puts '❌ Mockolo not found.'
        puts "\nInstall Mockolo:"
        puts '  brew install mockolo'
        return
      end

      if args.empty?
        print_mock_generator_help
        return
      end

      target, protocol, output_dir = parse_mock_options(args)
      FileUtils.mkdir_p(output_dir)
      output_file = File.join(output_dir, 'Mocks.swift')

      if target
        generate_mocks_for_target(target, output_file, output_dir)
      elsif protocol
        generate_mock_for_protocol(protocol, output_file, output_dir)
      else
        puts '❌ Must specify --target or --protocol'
      end
    end

    def verify_mocks
      puts '🎭 --- [ MOCK SYNCHRONIZATION CHECK ] ---'

      unless system('which mockolo > /dev/null 2>&1')
        puts '❌ Mockolo not found. Install: brew install mockolo'
        return
      end

      puts '📂 Scanning for @mockable protocols...'
      # Search in both root and SaneBar/ subdirectory for different project structures
      protocol_files = `find . -name "*.swift" -not -path "./Tests/*" -not -path "./.build/*" -exec grep -l "@mockable" {} \\; 2>/dev/null`.strip.split("\n")

      if protocol_files.empty?
        puts '⚠️  No @mockable protocols found'
        return
      end

      puts "   Found #{protocol_files.length} protocol(s) with @mockable"
      puts ''

      mocks_file = 'SaneBarTests/Mocks/Mocks.swift'
      unless File.exist?(mocks_file)
        puts "❌ Mocks file not found: #{mocks_file}"
        puts '   Run: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
        return
      end

      compare_mocks(mocks_file)
    end

    def check_protocol_changes(files)
      return if files.empty?

      protocol_files = files.select do |file|
        file.include?('Protocol') && file.end_with?('.swift') && File.exist?(file)
      end
      return if protocol_files.empty?

      changed_mockable = protocol_files.select do |file|
        content = File.read(file)
        content.include?('@mockable') || content.include?('protocol')
      end
      return unless changed_mockable.any?

      puts "\n⚠️  Protocol files with @mockable were modified:"
      changed_mockable.each { |f| puts "   - #{f}" }
      puts "\n💡 Remember to regenerate mocks:"
      puts '   ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
      puts "\n   (This is a reminder - commit will proceed)"
    end

    private

    def print_mock_generator_help
      puts 'Usage: ./Scripts/SaneMaster.rb gen_mock [options]'
      puts ''
      puts 'Options:'
      puts '  --target <dir>        Generate mocks for all protocols in directory'
      puts '  --protocol <name>     Generate mock for specific protocol'
      puts '  --output <dir>        Output directory (default: SaneBarTests/Mocks)'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_mock --target Services/Camera'
      puts '  ./Scripts/SaneMaster.rb gen_mock --protocol CameraServiceProtocol'
    end

    def parse_mock_options(args)
      target = nil
      protocol = nil
      # Use Tests/Mocks or SaneBarTests/Mocks depending on project structure
      output_dir = File.directory?('Tests') ? 'Tests/Mocks' : 'SaneBarTests/Mocks'

      args.each_with_index do |arg, i|
        case arg
        when '--target' then target = args[i + 1] if args[i + 1]
        when '--protocol' then protocol = args[i + 1] if args[i + 1]
        when '--output' then output_dir = args[i + 1] if args[i + 1]
        end
      end

      [target, protocol, output_dir]
    end

    def generate_mocks_for_target(target, output_file, output_dir)
      puts "Generating mocks for target: #{target}"
      # Try target directly first, then with SaneBar/ prefix (for different project structures)
      source_dir = if File.directory?(target)
                     target
                   elsif File.directory?("SaneBar/#{target}")
                     "SaneBar/#{target}"
                   end
      unless source_dir
        puts "❌ Directory not found: #{target} or SaneBar/#{target}"
        return
      end

      cmd = "mockolo -s #{source_dir} -d #{output_file} --enable-args-history --mock-all"
      puts "Running: #{cmd}"

      if system(cmd)
        post_process_mocks(output_file)
        puts '✅ Mocks generated successfully'
        print_mock_next_steps(output_dir)
      else
        puts '❌ Mock generation failed'
      end
    end

    def generate_mock_for_protocol(protocol, output_file, output_dir)
      puts "Generating mock for protocol: #{protocol}"
      protocol_file = `find . -name "*.swift" -not -path "./Tests/*" -not -path "./.build/*" -exec grep -l "protocol #{protocol}" {} \\; 2>/dev/null`.strip

      if protocol_file.empty?
        puts "❌ Protocol not found: #{protocol}"
        return
      end

      protocol_dir = File.dirname(protocol_file)
      cmd = "mockolo -s #{protocol_dir} -d #{output_file} --enable-args-history --mock-all -i #{protocol}"
      puts "Running: #{cmd}"

      if system(cmd)
        post_process_mocks(output_file)
        puts '✅ Mocks generated successfully'
        print_mock_next_steps(output_dir)
      else
        puts '❌ Mock generation failed'
      end
    end

    def post_process_mocks(output_file)
      return unless File.exist?(output_file)

      content = File.read(output_file)
      content.gsub!(/^import [A-Za-z]+ [A-Za-z]+.*\n/, '')
      content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneBar\n") unless content.include?('@testable import SaneBar')
      File.write(output_file, content)
    end

    def print_mock_next_steps(output_dir)
      puts "\n✅ Mocks generated in: #{output_dir}"
      puts "\n📝 Next steps:"
      puts '  1. Review generated mocks'
      puts '  2. Import in your test files'
      puts '  3. Use in tests: let mock = MockCameraService()'
    end

    def compare_mocks(mocks_file)
      puts '🔄 Generating temporary mocks for comparison...'
      temp_dir = Dir.mktmpdir
      temp_mocks = File.join(temp_dir, 'Mocks.swift')

      # Use Core/Services or SaneBar/Core/Protocols depending on project structure
      protocols_dir = File.directory?('Core/Services') ? 'Core/Services' : 'SaneBar/Core/Protocols'
      cmd = "mockolo -s #{protocols_dir} -d #{temp_mocks} --enable-args-history --mock-all 2>/dev/null"
      unless system(cmd)
        puts '❌ Failed to generate temporary mocks'
        FileUtils.rm_rf(temp_dir)
        return
      end

      post_process_mocks(temp_mocks) if File.exist?(temp_mocks)

      existing_protocols = File.read(mocks_file).scan(/class (\w+ProtocolMock)/).flatten
      temp_protocols = File.read(temp_mocks).scan(/class (\w+ProtocolMock)/).flatten

      missing = temp_protocols - existing_protocols
      extra = existing_protocols - temp_protocols

      FileUtils.rm_rf(temp_dir)

      if missing.empty? && extra.empty?
        puts '✅ Mocks are synchronized with protocols'
      else
        puts '⚠️  Mocks may be out of sync:'
        puts "   Missing mocks: #{missing.join(', ')}" if missing.any?
        puts "   Extra mocks: #{extra.join(', ')}" if extra.any?
        puts "\n💡 Regenerate mocks: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols"
      end
    end
  end
end
