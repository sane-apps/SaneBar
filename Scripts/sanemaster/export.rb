# frozen_string_literal: true

module SaneMasterModules
  # PDF export using Prawn (pure Ruby, no external dependencies)
  # Generates compact, readable code PDFs for review
  module Export
    EXCLUDE_DIRS = %w[build .build DerivedData Pods .git SourcePackages checkouts artifacts .swiftpm].freeze
    EXCLUDE_PATTERNS = %w[Mock Generated Stub .generated. Package.swift XCTestManifests LinuxMain].freeze

    # Monokai-inspired colors for optional syntax highlighting
    SYNTAX_COLORS = {
      'Keyword' => '66d9ef', 'Name.Class' => 'a6e22e', 'Name.Function' => 'a6e22e',
      'Literal.String' => 'e6db74', 'Literal.Number' => 'ae81ff',
      'Comment' => '75715e', 'Operator' => 'f92672', 'Text' => '333333'
    }.freeze

    def export_pdf(args)
      puts '📚 --- [ SANEMASTER CODE EXPORT ] ---'

      options = parse_export_args(args)
      ensure_gems

      files = collect_swift_files(options[:include_tests])
      if files.empty?
        puts '❌ No Swift files found!'
        return
      end

      total_lines = files.sum { |_, content| content.lines.count }
      puts "   #{files.count} files, #{format_number(total_lines)} lines"

      puts '🎨 Generating PDF with Prawn...'

      timestamp = Time.now.strftime('%Y%m%d_%H%M')
      project_output = File.join(Dir.pwd, 'Output')
      FileUtils.mkdir_p(project_output)
      output_dir = options[:output] || project_output
      pdf_path = File.join(output_dir, "#{project_name}_Code_#{timestamp}.pdf")

      generate_pdf(files, pdf_path, highlight: options[:highlight])

      pdf_size = File.size(pdf_path) / (1024.0 * 1024)

      # Compress if too large
      if !options[:no_compress] && pdf_size > 20
        puts '🗜️  Compressing...'
        compressed = compress_pdf(pdf_path)
        pdf_size = File.size(pdf_path) / (1024.0 * 1024) if compressed
      end

      status = pdf_size < 20 ? '✅' : '⚠️ '
      puts "\n#{status} Done! #{File.basename(pdf_path)} (#{pdf_size.round(1)}MB)"
      system('open', pdf_path)
    end

    private

    def parse_export_args(args)
      options = { include_tests: false, no_compress: false, output: nil, highlight: false }

      args.each_with_index do |arg, i|
        case arg
        when '--include-tests', '-t'
          options[:include_tests] = true
        when '--no-compress'
          options[:no_compress] = true
        when '--highlight', '-h'
          options[:highlight] = true
        when '--output', '-o'
          options[:output] = args[i + 1]
        end
      end

      options
    end

    def ensure_gems
      %w[prawn].each do |gem_name|
        require gem_name
      rescue LoadError
        puts "   Installing #{gem_name} gem..."
        system("gem install #{gem_name} --no-document")
        Gem.clear_paths
        require gem_name
      end
    end

    def collect_swift_files(include_tests)
      files = []
      project_root = Dir.pwd

      Dir.glob(File.join(project_root, '**', '*.swift')).sort.each do |path|
        rel_path = path.sub("#{project_root}/", '')

        next if EXCLUDE_DIRS.any? { |dir| rel_path.include?(dir) }
        next if !include_tests && (rel_path.include?('Tests') || rel_path.end_with?('Test.swift'))
        next if EXCLUDE_PATTERNS.any? { |pat| rel_path.include?(pat) }

        content = File.read(path, encoding: 'UTF-8')
        next if content.strip.length < 50

        files << [rel_path, content]
      rescue StandardError => e
        puts "   Warning: Could not read #{rel_path}: #{e.message}"
      end

      files
    end

    def generate_pdf(files, pdf_path, highlight: false)
      require 'prawn'
      require 'rouge' if highlight

      total_lines = files.sum { |_, content| content.lines.count }
      lexer = Rouge::Lexers::Swift.new if highlight

      # Group files by directory
      grouped = files.group_by { |path, _| File.dirname(path) }

      Prawn::Document.generate(pdf_path, page_size: 'LETTER', margin: [36, 36, 50, 36]) do |pdf|
        # Register monospace font
        pdf.font_families.update(
          'Mono' => { normal: '/System/Library/Fonts/SFNSMono.ttf' }
        )

        # ═══════════════════════════════════════════════════════════
        # TITLE PAGE
        # ═══════════════════════════════════════════════════════════
        pdf.move_down 180

        pdf.font('Helvetica', size: 42, style: :bold)
        pdf.text project_name, align: :center, color: '1a1a1a'

        pdf.move_down 8
        pdf.font('Helvetica', size: 14)
        pdf.text 'Source Code Review', align: :center, color: '666666'

        pdf.move_down 40
        pdf.stroke_color 'cccccc'
        pdf.stroke_horizontal_rule
        pdf.move_down 40

        pdf.font('Helvetica', size: 11)
        pdf.text Time.now.strftime('%B %d, %Y'), align: :center, color: '888888'
        pdf.move_down 15

        # Stats box
        pdf.fill_color 'f5f5f5'
        pdf.fill_rounded_rectangle [(pdf.bounds.width / 2) - 100, pdf.cursor], 200, 50, 5
        pdf.fill_color '000000'

        pdf.move_down 15
        pdf.font('Helvetica', size: 12, style: :bold)
        pdf.text "#{files.count} files", align: :center, color: '333333'
        pdf.font('Helvetica', size: 10)
        pdf.text "#{format_number(total_lines)} lines of code", align: :center, color: '666666'

        # ═══════════════════════════════════════════════════════════
        # TABLE OF CONTENTS
        # ═══════════════════════════════════════════════════════════
        pdf.start_new_page

        pdf.font('Helvetica', size: 20, style: :bold)
        pdf.text 'Table of Contents', color: '1a1a1a'
        pdf.move_down 5
        pdf.stroke_color 'dddddd'
        pdf.stroke_horizontal_rule
        pdf.move_down 20

        grouped.each do |dir, dir_files|
          # Check if we need a new page for this directory
          pdf.start_new_page if pdf.cursor < 80

          # Directory header
          pdf.fill_color 'f0f0f0'
          pdf.fill_rounded_rectangle [0, pdf.cursor], pdf.bounds.width, 18, 3
          pdf.fill_color '000000'

          pdf.move_down 4
          pdf.font('Helvetica', size: 10, style: :bold)
          pdf.indent(8) { pdf.text "#{dir}/", color: '2a2a2a' }
          pdf.move_down 8

          # Files in directory
          pdf.font('Helvetica', size: 9)
          dir_files.each do |path, content|
            lines = content.lines.count
            filename = File.basename(path)

            pdf.indent(16) do
              pdf.text filename.to_s, color: '444444', inline_format: true
              # Add line count on same line (right-aligned conceptually via spacing)
              pdf.move_up 10
              pdf.text "#{lines} lines", align: :right, color: '999999', size: 8
              pdf.move_down 2
            end
          end
          pdf.move_down 10
        end

        # ═══════════════════════════════════════════════════════════
        # CODE SECTIONS
        # ═══════════════════════════════════════════════════════════
        files.each do |path, content|
          pdf.start_new_page

          # File header bar
          pdf.fill_color '2d2d2d'
          pdf.fill_rectangle [pdf.bounds.left, pdf.cursor], pdf.bounds.width, 24
          pdf.fill_color '000000'

          pdf.font('Mono', size: 10) do
            pdf.bounding_box([8, pdf.cursor - 6], width: pdf.bounds.width - 16, height: 14) do
              pdf.fill_color 'ffffff'
              pdf.text path
              pdf.fill_color '000000'
            end
          end

          pdf.move_down 30

          # Line count badge
          lines = content.lines.count
          pdf.fill_color 'eeeeee'
          pdf.fill_rounded_rectangle [pdf.bounds.width - 70, pdf.cursor + 5], 70, 16, 3
          pdf.fill_color '000000'
          pdf.font('Helvetica', size: 8) do
            pdf.text_box "#{lines} lines", at: [pdf.bounds.width - 65, pdf.cursor + 2], width: 60, align: :center,
                                           color: '666666'
          end

          pdf.move_down 10

          # Code content
          if highlight
            render_code_highlighted(pdf, content, lexer)
          else
            render_code(pdf, content)
          end
        end

        # ═══════════════════════════════════════════════════════════
        # PAGE NUMBERS (footer)
        # ═══════════════════════════════════════════════════════════
        pdf.number_pages 'Page <page> of <total>',
                         at: [pdf.bounds.right - 100, -20],
                         width: 100,
                         align: :right,
                         size: 8,
                         color: '999999'
      end
    end

    def render_code(pdf, content)
      pdf.font('Mono', size: 7) do
        pdf.fill_color '333333'

        # Batch render all lines at once for compact PDF
        formatted = content.lines.map.with_index(1) do |line, num|
          "#{num.to_s.rjust(4)}  #{line.chomp}"
        end.join("\n")

        pdf.text formatted, leading: 2
      end
    end

    def render_code_highlighted(pdf, content, lexer)
      pdf.font('Mono', size: 7) do
        content.lines.each_with_index do |line, idx|
          pdf.start_new_page if pdf.cursor < 30

          # Line number
          pdf.fill_color '888888'
          pdf.text_box (idx + 1).to_s.rjust(4), at: [0, pdf.cursor], width: 25

          # Highlighted tokens
          tokens = lexer.lex(line.chomp)
          fragments = tokens.map do |token, text|
            color = SYNTAX_COLORS.find { |k, _| token.qualname.start_with?(k) }&.last || '333333'
            { text: text, color: color, font: 'Mono' }
          end
          fragments = [{ text: line.chomp, color: '333333', font: 'Mono' }] if fragments.empty?

          pdf.formatted_text_box fragments, at: [30, pdf.cursor], width: pdf.bounds.width - 30,
                                            height: 10, overflow: :shrink_to_fit, single_line: true
          pdf.move_down 9
        end
      end
    end

    # rubocop:disable Naming/PredicateMethod -- returns success, not a predicate
    def compress_pdf(pdf_path)
      gs = ['/opt/homebrew/bin/gs', '/usr/local/bin/gs'].find { |p| File.exist?(p) }
      return false unless gs

      compressed_path = pdf_path.sub('.pdf', '_tmp.pdf')
      original_size = File.size(pdf_path)

      success = system(
        gs,
        '-sDEVICE=pdfwrite',
        '-dCompatibilityLevel=1.4',
        '-dPDFSETTINGS=/ebook',
        '-dNOPAUSE',
        '-dQUIET',
        '-dBATCH',
        "-sOutputFile=#{compressed_path}",
        pdf_path,
        out: File::NULL,
        err: File::NULL
      )

      return false unless success && File.exist?(compressed_path)

      compressed_size = File.size(compressed_path)

      if compressed_size < original_size
        File.delete(pdf_path)
        File.rename(compressed_path, pdf_path)
        puts "   #{(original_size / 1024.0 / 1024).round(1)}MB → #{(compressed_size / 1024.0 / 1024).round(1)}MB"
        true
      else
        File.delete(compressed_path)
        false
      end
    end
    # rubocop:enable Naming/PredicateMethod

    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
