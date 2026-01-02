# frozen_string_literal: true

module SaneMasterModules
  # Template management: save, apply, list project configurations
  module GenerationTemplates
    include Base

    def manage_templates(args)
      ensure_template_dir
      subcommand = args.shift || 'list'

      case subcommand
      when 'save' then save_template(args.first || 'default')
      when 'apply' then apply_template(args.first || 'default')
      when 'list' then list_templates
      when 'delete' then delete_template(args.first)
      else
        puts "Unknown template command: #{subcommand}"
        puts 'Usage: template [save|apply|list|delete] [name]'
      end
    end

    private

    def ensure_template_dir
      FileUtils.mkdir_p(TEMPLATE_DIR)
    end

    def save_template(name)
      puts "📦 --- [ SAVE TEMPLATE: #{name} ] ---"

      template_path = File.join(TEMPLATE_DIR, name)
      FileUtils.mkdir_p(template_path)

      template_files = {
        'Gemfile' => 'Gemfile',
        '.ruby-version' => '.ruby-version',
        '.swiftlint.yml' => '.swiftlint.yml',
        'project.yml' => 'project.yml',
        '.mcp.json' => '.mcp.json',
        'lefthook.yml' => 'lefthook.yml',
        '.claude/settings.json' => '.claude/settings.json'
      }

      saved = copy_template_files(template_files, template_path)
      save_template_metadata(name, template_path, saved)

      puts "✅ Template saved: #{template_path}"
      puts "   Files: #{saved.join(', ')}"
      puts "\n💡 Apply to new project: ./Scripts/SaneMaster.rb template apply #{name}"
    end

    def copy_template_files(template_files, template_path)
      saved = []
      template_files.each do |src, dest|
        src_path = File.join(Dir.pwd, src)
        next unless File.exist?(src_path)

        dest_path = File.join(template_path, dest)
        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(src_path, dest_path)
        saved << src
      end
      saved
    end

    def save_template_metadata(name, template_path, saved)
      metadata = {
        name: name,
        created_at: Time.now.iso8601,
        source_project: File.basename(Dir.pwd),
        files: saved
      }
      File.write(File.join(template_path, 'metadata.json'), JSON.pretty_generate(metadata))
    end

    def apply_template(name)
      puts "📥 --- [ APPLY TEMPLATE: #{name} ] ---"

      template_path = File.join(TEMPLATE_DIR, name)
      unless File.exist?(template_path)
        puts "❌ Template not found: #{name}"
        list_templates
        return
      end

      show_template_metadata(template_path)
      applied = apply_template_files(template_path)

      if applied.any?
        puts "\n✅ Applied files:"
        applied.each { |f| puts "   - #{f}" }
        puts "\n💡 Run ./Scripts/SaneMaster.rb bootstrap to complete setup"
      else
        puts '⚠️  No new files applied (all exist already)'
      end
    end

    def show_template_metadata(template_path)
      metadata_file = File.join(template_path, 'metadata.json')
      return unless File.exist?(metadata_file)

      metadata = JSON.parse(File.read(metadata_file))
      puts "📋 Template from: #{metadata['source_project']} (#{metadata['created_at']})"
    end

    def apply_template_files(template_path)
      applied = []
      Dir.glob(File.join(template_path, '**/*')).each do |src|
        next if File.directory?(src)
        next if src.end_with?('metadata.json')

        relative = src.sub("#{template_path}/", '')
        dest = File.join(Dir.pwd, relative)

        if File.exist?(dest)
          puts "   ⚠️  Skipping (exists): #{relative}"
          next
        end

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
        applied << relative
      end
      applied
    end

    def list_templates
      puts '📋 --- [ AVAILABLE TEMPLATES ] ---'

      templates = Dir.glob(File.join(TEMPLATE_DIR, '*')).select { |f| File.directory?(f) }

      if templates.empty?
        puts '   No templates saved yet.'
        puts "\n💡 Save current project as template: ./Scripts/SaneMaster.rb template save mytemplate"
        return
      end

      templates.each { |template_path| display_template(template_path) }
    end

    def display_template(template_path)
      name = File.basename(template_path)
      metadata_file = File.join(template_path, 'metadata.json')

      if File.exist?(metadata_file)
        metadata = JSON.parse(File.read(metadata_file))
        puts "   #{name}"
        puts "      From: #{metadata['source_project']}"
        puts "      Created: #{metadata['created_at']}"
        puts "      Files: #{metadata['files']&.count || '?'}"
      else
        puts "   #{name} (no metadata)"
      end
      puts ''
    end

    def delete_template(name)
      return puts '❌ Specify template name to delete' unless name

      template_path = File.join(TEMPLATE_DIR, name)
      unless File.exist?(template_path)
        puts "❌ Template not found: #{name}"
        return
      end

      FileUtils.rm_rf(template_path)
      puts "✅ Deleted template: #{name}"
    end
  end
end
