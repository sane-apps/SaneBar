# frozen_string_literal: true

module SaneMasterModules
  # Markdown to PDF export using Prawn
  module MdExport
    def export_markdown(args)
      require 'prawn'
      require 'prawn/table'
      Prawn::Fonts::AFM.hide_m17n_warning = true

      input_file = args.find { |a| a.end_with?('.md') }
      unless input_file && File.exist?(input_file)
        puts 'Usage: ./Scripts/SaneMaster.rb md_export <file.md>'
        puts '       Converts markdown to PDF'
        return
      end

      output_file = args.find { |a| a.start_with?('--output=') }&.split('=', 2)&.last
      unless output_file
        # Default to project Output/ folder
        project_output = File.join(Dir.pwd, 'Output')
        FileUtils.mkdir_p(project_output)
        output_file = File.join(project_output, File.basename(input_file).sub('.md', '.pdf'))
      end

      puts "📄 Converting: #{File.basename(input_file)}"
      content = File.read(input_file)
      # Strip non-ASCII for Prawn compatibility (built-in fonts don't support Unicode)
      content = content.encode('ASCII', invalid: :replace, undef: :replace, replace: '')
                       .gsub(/[^\x20-\x7E\n\r\t]/, '')

      generate_markdown_pdf(content, output_file)

      puts "✅ Created: #{output_file}"
      system('open', output_file)
    end

    private

    def generate_markdown_pdf(content, output_path)
      Prawn::Document.generate(output_path, page_size: 'LETTER', margin: [50, 50, 50, 50]) do |pdf|
        pdf.font_families.update(
          'Helvetica' => {
            normal: 'Helvetica',
            bold: 'Helvetica-Bold',
            italic: 'Helvetica-Oblique',
            bold_italic: 'Helvetica-BoldOblique'
          }
        )

        lines = content.split("\n")
        in_code_block = false
        in_table = false
        table_rows = []

        lines.each do |line|
          # Code blocks
          if line.strip.start_with?('```')
            if in_code_block
              in_code_block = false
              pdf.move_down 8
            else
              in_code_block = true
              pdf.move_down 4
              pdf.fill_color 'f5f5f5'
            end
            next
          end

          if in_code_block
            pdf.font('Courier', size: 8) do
              pdf.fill_color '333333'
              pdf.text line, leading: 1
            end
            next
          end

          # Tables
          if line =~ /^\|.+\|$/
            cells = line.split('|').map(&:strip).reject(&:empty?)
            # Skip separator rows
            table_rows << cells unless cells.all? { |c| c =~ /^[-:]+$/ }
            in_table = true
            next
          elsif in_table && line.strip.empty?
            # End of table - render it
            render_table(pdf, table_rows) if table_rows.any?
            table_rows = []
            in_table = false
            pdf.move_down 8
            next
          end

          # Headings
          case line
          when /^# (.+)/
            pdf.move_down 15
            pdf.font('Helvetica', size: 24, style: :bold) { pdf.text ::Regexp.last_match(1), color: '1a1a1a' }
            pdf.move_down 5
            pdf.stroke_color '333333'
            pdf.stroke_horizontal_rule
            pdf.move_down 15
          when /^## (.+)/
            pdf.start_new_page if pdf.cursor < 100
            pdf.move_down 15
            pdf.font('Helvetica', size: 18, style: :bold) { pdf.text ::Regexp.last_match(1), color: '2a2a2a' }
            pdf.move_down 8
          when /^### (.+)/
            pdf.start_new_page if pdf.cursor < 80
            pdf.move_down 12
            pdf.font('Helvetica', size: 14, style: :bold) { pdf.text ::Regexp.last_match(1), color: '333333' }
            pdf.move_down 6
          when /^#### (.+)/
            pdf.move_down 8
            pdf.font('Helvetica', size: 12, style: :bold) { pdf.text ::Regexp.last_match(1), color: '444444' }
            pdf.move_down 4
          when /^---$/
            pdf.move_down 10
            pdf.stroke_color 'cccccc'
            pdf.stroke_horizontal_rule
            pdf.move_down 10
          when /^\s*$/
            pdf.move_down 4
          when /^- (.+)/, /^\* (.+)/
            text = format_inline(::Regexp.last_match(1))
            pdf.font('Helvetica', size: 10) do
              pdf.indent(15) { pdf.text "• #{text}", inline_format: true, leading: 2 }
            end
            pdf.move_down 2
          when /^\d+\. (.+)/
            text = format_inline(::Regexp.last_match(1))
            pdf.font('Helvetica', size: 10) { pdf.text line.sub(/^\d+\. /, '').then { |t| format_inline(t) }, inline_format: true }
            pdf.move_down 2
          else
            next if line.strip.empty?

            text = format_inline(line)
            pdf.font('Helvetica', size: 10) { pdf.text text, inline_format: true, leading: 2 }
            pdf.move_down 3
          end
        end

        # Render any remaining table
        render_table(pdf, table_rows) if table_rows.any?

        pdf.number_pages 'Page <page> of <total>',
                         at: [pdf.bounds.right - 100, -30],
                         size: 8,
                         color: '888888'
      end
    end

    def format_inline(text)
      text.gsub(/\*\*(.+?)\*\*/, '<b>\1</b>')
          .gsub(/\*(.+?)\*/, '<i>\1</i>')
          .gsub(/\[(.+?)\]\(.+?\)/, '\1')
          .gsub(/`(.+?)`/, '<font name="Courier">\1</font>')
          .gsub(/[^\x00-\x7F]/, '') # Strip non-ASCII (emojis)
    end

    def render_table(pdf, rows)
      return if rows.empty?

      pdf.move_down 8

      table_data = rows.map do |row|
        row.map { |cell| format_inline(cell) }
      end

      pdf.table(table_data, width: pdf.bounds.width, cell_style: {
                  size: 9,
                  padding: [5, 8],
                  inline_format: true
                }) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = 'f0f0f0'
        t.cells.borders = [:bottom]
        t.cells.border_color = 'dddddd'
      end

      pdf.move_down 8
    end
  end
end
