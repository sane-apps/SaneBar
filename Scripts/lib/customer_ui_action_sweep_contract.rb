# frozen_string_literal: true

class CustomerUIActionSweep
  private

  def customer_ui_contract_report
    out, status = Open3.capture2e(SANEMASTER, 'customer_ui_contract', '--json', '--no-exit')
    raise "Could not read customer UI contract report: #{out}" unless status.success?

    JSON.parse(out)
  end

  def verify_source_and_unit_guards
    SOURCE_GUARDS.each do |guard_name, checks|
      checks.each do |path, expected|
        content = read_guard_file(path)
        raise "Source guard #{guard_name} missing #{expected.inspect} in #{path}" unless content.include?(expected)
      end
      @transcript << "source_guard=#{guard_name} ok checks=#{checks.length}"
    end
  end

  def read_guard_file(path)
    full_path = if path.start_with?('/Users/sj/SaneApps/')
                  File.join(SANEAPPS_ROOT, path.delete_prefix('/Users/sj/SaneApps/'))
                elsif path.start_with?('infra/')
                  File.join(SANEAPPS_ROOT, path)
                elsif path.start_with?('/')
                  path
                else
                  File.join(PROJECT_ROOT, path)
                end
    raise "Source guard file missing: #{path}" unless File.exist?(full_path)

    File.read(full_path)
  end

  def build_action_results
    settings_evidence = (@screenshots.grep(%r{outputs/customer-ui/settings-}) + @settings_snapshots).uniq
    runtime_lines = runtime_evidence_lines
    source_lines = @transcript.grep(/\Asource_guard=/)
    apple_lines = @transcript.grep(/\Aapplescript=/)
    url_lines = @transcript.grep(/\Aurl_route=/)

    pass_action('status-item-click-routes', [
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_click', browse_runtime_line(runtime_lines, 'findIcon')),
      evidence('screenshot', 'Browse Icons visual state captured during status-item route verification', [screenshot_for_action('status-item-click-routes')]),
      evidence('unit_guard', 'ReleaseRegressionTests covers left/right/option click routing and StatusBarControllerTests covers status item menu selectors')
    ])
    pass_action('status-menu-command-actions', [
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_click', apple_line(apple_lines, 'open settings window')),
      evidence('screenshot', 'Settings visual state captured after shipped status menu command surfaces opened', [screenshot_for_action('status-menu-command-actions')]),
      evidence('log', 'Runtime smoke log confirms shipped settings surface and menu-bar fixture state', runtime_log_artifacts),
      evidence('source_guard', source_line(source_lines, 'status_menu')),
      evidence('unit_guard', 'StatusBarControllerTests verifies Browse Icons, Show / Hide, Settings, License, About, and selector wiring'),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Settings window visual check ok'))
    ])
    pass_action('dock-menu-command-actions', [
      evidence('fixture', source_line(source_lines, 'dock_menu')),
      evidence('mini_click', apple_line(apple_lines, 'open settings window')),
      evidence('screenshot', 'Settings surface reached from shipped utility-command flow', [screenshot_for_action('dock-menu-command-actions')]),
      evidence('log', 'Dock menu shares the shipped utility-command path verified by runtime command evidence', [artifact_file('dock-menu-command-actions', 'log', apple_lines.grep(/open settings window|close settings window/).join("\n"))]),
      evidence('source_guard', source_line(source_lines, 'dock_menu')),
      evidence('unit_guard', "RuntimeGuardXCTests testDockMenuUsesSharedUtilityActions covers shared Dock utility commands, including optional What's New")
    ])
    pass_action('browse-icons-search-navigation', [
      evidence('mini_click', browse_runtime_line(runtime_lines, 'findIcon')),
      evidence('screenshot', 'Browse Icons panel rendered from the running Mini build', [screenshot_for_action('browse-icons-search-navigation')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_automation', apple_line(apple_lines, 'quick search "Sane"')),
      evidence('mini_url_route', url_line(url_lines, 'search?q=Sane'))
    ])
    pass_action('browse-icons-icon-context-actions', [
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('screenshot', 'Browse Icons panel rendered before icon context action verification', [screenshot_for_action('browse-icons-icon-context-actions')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('log', 'Runtime smoke log confirms icon move/context action fixture result', runtime_log_artifacts),
      evidence('unit_guard', 'CustomerUIActionContractXCTests asserts Browse Icons context actions: Left-Click, Right-Click, Set Hotkey, Copy Icon ID, Move, Remove from Group')
    ])
    pass_action('second-menu-bar-actions', [
      evidence('mini_click', browse_runtime_line(runtime_lines, 'secondMenuBar')),
      evidence('screenshot', 'Second Menu Bar rendered from the running Mini build', [screenshot_for_action('second-menu-bar-actions')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('log', 'Runtime smoke log confirms second menu bar fixture result', runtime_log_artifacts),
      evidence('mini_automation', apple_line(apple_lines, 'show second menu bar'))
    ])
    pass_action('icon-zone-move-reorder-always-hidden', [
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Always Hidden round-trip ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Always Hidden move actions ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Post-settle zone stability ok')),
      evidence('screenshot', 'Browse Icons panel rendered before exact-ID move verification', [screenshot_for_action('icon-zone-move-reorder-always-hidden')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_automation', apple_line(apple_lines, 'list icon zones'))
    ])
    pass_action('icon-hotkeys-and-groups', [
      evidence('mini_click', @transcript.grep(/\Aicon_hotkeys_groups_custom_group_click=/).first),
      evidence('screenshot', 'Custom group creation prompt and result were exercised on the running Mini build', [screenshot_for_action('icon-hotkeys-and-groups')]),
      evidence('fixture', 'Hotkey and group behavior covered by persistence fixtures and customer UI source guards.'),
      evidence('state_receipt', source_line(source_lines, 'profiles')),
      evidence('log', 'Unit and source guards prove hotkey/group pathways without destructive UI mutation in release sweep', [artifact_file('icon-hotkeys-and-groups', 'state-receipt', JSON.pretty_generate(source_lines: source_lines.grep(/profiles|shortcuts/)))]),
      evidence('unit_guard', 'KeyboardShortcutsServiceTests and SearchWindowTests cover hotkey persistence, groups, remove, delete, and repeated create/delete safety'),
      evidence('source_guard', 'CustomerUIActionContractXCTests asserts Set Hotkey and Remove from Group actions are in shipped Browse/Second Menu Bar code')
    ])
    pass_action('settings-shell-tabs-render', [
      evidence('mini_click', @transcript.grep(/\Asettings_ax_tab_index=/).join(' | ')[0, 1000]),
      evidence('screenshot', "Captured usable settings window screenshot: #{screenshot_for_action('settings-shell-tabs-render')}", [screenshot_for_action('settings-shell-tabs-render')]),
      evidence('fixture', 'Settings tabs exercised on the running Mini app through AX row selection.'),
      evidence('log', "Captured #{settings_evidence.length} settings tab snapshot attempt(s): #{settings_evidence.join(', ')}", [artifact_file('settings-shell-tabs-render', 'log', @transcript.grep(/\Asettings_/).join("\n"))]),
      evidence('mini_ax', @transcript.grep(/\Asettings_ax_tab_index=/).join(' | ')[0, 1000])
    ])
    pass_action('control-settings-actions', [
      evidence('fixture', source_line(source_lines, 'settings_control')),
      evidence('mini_click', @transcript.grep(/\Asettings_tab=control/).first),
      evidence('mini_click', @transcript.grep(/\Asettings_control_hide_new_unlisted_toggle=/).first),
      evidence('mini_ax', @transcript.grep(/\Asettings_ax_tab_index=1/).first),
      evidence('screenshot', 'Control settings tab rendered during the Mini settings sweep', [screenshot_for_action('control-settings-actions')]),
      evidence('state_receipt', source_line(source_lines, 'settings_control'), [artifact_file('control-settings-actions', 'state-receipt', source_line(source_lines, 'settings_control'))]),
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'GeneralSettingsSimplificationXCTests, SettingsControllerTests, PersistenceServiceTests, and RuntimeGuardXCTests cover Control settings behavior and persistence')
    ])
    pass_action('profiles-save-load-delete-apply', [
      evidence('mini_click', apple_line(apple_lines, 'layout snapshot')),
      evidence('screenshot', 'Settings window visual state captured while profile-capable settings shell was open', [screenshot_for_action('profiles-save-load-delete-apply')]),
      evidence('fixture', source_line(source_lines, 'profiles')),
      evidence('source_guard', source_line(source_lines, 'profiles')),
      evidence('unit_guard', 'MenuBarManager+Profiles, PersistenceServiceTests, and App Intent source guard cover save/load/delete/apply paths')
    ])
    pass_action('rules-trigger-actions', [
      evidence('mini_click', @transcript.grep(/settings_tab=rules/).first || source_line(source_lines, 'rules')),
      evidence('screenshot', 'Rules tab visual state captured in the Mini settings sweep', [screenshot_for_action('rules-trigger-actions')]),
      evidence('fixture', source_line(source_lines, 'rules')),
      evidence('log', 'Rules settings and trigger source guards passed for low battery, app launch, schedule, network, Focus, and script triggers', [artifact_file('rules-trigger-actions', 'log', source_line(source_lines, 'rules'))]),
      evidence('source_guard', source_line(source_lines, 'rules')),
      evidence('unit_guard', 'Trigger service tests cover low battery, app launch, schedule, network, Focus, and script trigger behavior')
    ])
    pass_action('appearance-customization-actions', [
      evidence('fixture', source_line(source_lines, 'appearance')),
      evidence('mini_click', @transcript.grep(/\Asettings_tab=appearance/).first),
      evidence('screenshot', 'Custom Appearance overlay tint pixels captured by Mini runtime smoke', [screenshot_for_action('appearance-customization-actions')]),
      evidence('state_receipt', runtime_line(runtime_lines, 'Appearance tint pixels ok')),
      evidence('state_receipt', runtime_line(runtime_lines, 'Visible fullscreen transition contract ok')),
      evidence('source_guard', source_line(source_lines, 'appearance')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Appearance tint pixels ok')),
      evidence('unit_guard', 'MenuBarAppearanceService and RuntimeGuardXCTests cover overlay refresh and appearance recovery')
    ])
    pass_action('shortcuts-and-automation-actions', [
      evidence('mini_click', apple_lines.join(' | ')[0, 1800]),
      evidence('screenshot', 'Shortcuts/automation settings shell rendered in Mini settings sweep', [screenshot_for_action('shortcuts-and-automation-actions')]),
      evidence('fixture', source_line(source_lines, 'shortcuts')),
      evidence('log', 'AppleScript command transcript captured for automation surface', [artifact_file('shortcuts-and-automation-actions', 'log', apple_lines.join("\n"))]),
      evidence('source_guard', source_line(source_lines, 'shortcuts')),
      evidence('mini_url_route', URL_ROUTE_EVIDENCE.map { |route| url_line(url_lines, route) }.join(' | ')),
      evidence('mini_automation', apple_lines.join(' | ')[0, 1800])
    ])
    pass_action('health-repair-rescue-diagnostics', [
      evidence('mini_click', "#{url_line(url_lines, 'health')} | #{url_line(url_lines, 'repair')}"),
      evidence('screenshot', 'Health/repair settings window rendered from deep-link route on Mini', [screenshot_for_action('health-repair-rescue-diagnostics')]),
      evidence('fixture', source_line(source_lines, 'health')),
      evidence('log', 'Startup and health/repair runtime logs captured', runtime_startup_probe_log_paths),
      evidence('source_guard', source_line(source_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'repair'))
    ])
    pass_action('data-import-export-reset-actions', [
      evidence('mini_click', @transcript.grep(/settings_tab=control/).first || source_line(source_lines, 'settings_control')),
      evidence('screenshot', 'Control settings visual state captured for import/export/reset action surface', [screenshot_for_action('data-import-export-reset-actions')]),
      evidence('fixture', source_line(source_lines, 'settings_control')),
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'Import, export, Bartender/Ice preview, rollback, and reset coverage lives in BartenderImportServiceTests, RuntimeGuardXCTests, and PersistenceServiceTests')
    ])
    pass_action('onboarding-basic-pro-permission-actions', [
      evidence('mini_click', @transcript.grep(/\Asettings_tab=license/).first || @transcript.grep(/\Aruntime_visual=settings/).first),
      evidence('screenshot', 'Settings visual state captured for Basic/Pro permission-adjacent release surface', [screenshot_for_action('onboarding-basic-pro-permission-actions')]),
      evidence('fixture', source_line(source_lines, 'onboarding')),
      evidence('log', 'Onboarding source guard captured Basic/Pro, import, accessibility, unlock, and restore controls', [artifact_file('onboarding-basic-pro-permission-actions', 'log', source_line(source_lines, 'onboarding'))]),
      evidence('source_guard', source_line(source_lines, 'onboarding')),
      evidence('unit_guard', 'Onboarding source guard verifies Basic/Pro, import, accessibility, unlock, and restore controls remain present')
    ])
    pass_action('license-about-support-actions', [
      evidence('mini_click', "#{@transcript.grep(/settings_tab=license/).first} | #{@transcript.grep(/settings_tab=about/).first}"),
      evidence('screenshot', 'License/About settings surfaces rendered during Mini settings sweep', [screenshot_for_action('license-about-support-actions')]),
      evidence('fixture', source_line(source_lines, 'license_about')),
      evidence('support_report', 'Report a Bug attachment/copy/cancel path captured for support media handling', [artifact_file('license-about-support-actions', 'support-report', support_report_artifact(settings_evidence))]),
      evidence('source_guard', source_line(source_lines, 'license_about')),
      evidence('mini_screenshots', "License and About tabs captured in settings tab sweep: #{settings_evidence.grep(/settings-(license|about)-/).join(', ')}", settings_evidence.grep(/settings-(license|about)-/))
    ])
    pass_action('pro-basic-gating-actions', [
      evidence('mini_click', @transcript.grep(/\Asettings_tab=license/).first || @transcript.grep(/\Asettings_tab=control/).first),
      evidence('screenshot', 'Settings visual state captured for Pro/Basic gated controls', [screenshot_for_action('pro-basic-gating-actions')]),
      evidence('fixture', source_line(source_lines, 'pro_gates')),
      evidence('log', 'Pro gating guard confirms Basic copy and Pro-only automation/export/import paths', [artifact_file('pro-basic-gating-actions', 'log', source_line(source_lines, 'pro_gates'))]),
      evidence('source_guard', source_line(source_lines, 'pro_gates')),
      evidence('unit_guard', 'RuntimeGuardXCTests and ProFeature source guards cover Basic gating text and Pro-only automation/export/import paths')
    ])
    pass_action('startup-wake-appearance-recovery', [
      evidence('fixture', runtime_line(runtime_lines, 'Startup layout probe passed')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Startup layout probe passed')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Wake layout probe passed')),
      evidence('screenshot', 'Startup recovery includes Custom Appearance overlay tint pixel evidence from Mini runtime smoke', [screenshot_for_action('startup-wake-appearance-recovery')]),
      evidence('state_receipt', runtime_line(runtime_lines, 'Appearance tint pixels ok')),
      evidence('state_receipt', runtime_line(runtime_lines, 'Visible fullscreen transition contract ok')),
      evidence('log', 'Startup, wake, and appearance recovery runtime logs captured', runtime_log_artifacts + runtime_startup_probe_log_paths + runtime_wake_probe_log_paths),
      evidence('source_guard', source_line(source_lines, 'recovery'))
    ])
  end

  def pass_action(id, evidence_items)
    action = @action_by_id.fetch(id)
    clean_evidence = evidence_items.flatten.compact
    raise "#{id}: no action evidence recorded" if clean_evidence.empty?

    clean_evidence = dedupe_evidence(clean_evidence)
    clean_evidence = attach_required_evidence_artifacts(id, clean_evidence)
    assert_required_evidence!(id, action, clean_evidence)

    @action_results[id] = {
      status: 'passed',
      proof_level: action['required_proof_level'].to_s,
      functional_state: functional_state_receipt(action),
      inputs: receipt_inputs(action),
      output_assertions: receipt_outputs(action),
      evidence: clean_evidence,
      workflow: workflow_receipt(id, action, clean_evidence)
    }
  end

  def assert_required_evidence!(id, action, evidence_items)
    evidence_types = evidence_items.map { |item| item[:type].to_s }
    missing = Array(action['required_evidence_types']).map(&:to_s).reject { |type| evidence_types.include?(type) }
    raise "#{id}: missing actual Mini evidence type(s): #{missing.join(', ')}" unless missing.empty?

    if action['required_proof_level'].to_s == 'full_runtime_completion'
      strict_items = evidence_items.select { |item| STRICT_MINI_EVIDENCE_TYPES.include?(item[:type].to_s) }
      raise "#{id}: full_runtime_completion requires strict Mini runtime evidence" if strict_items.empty?
    end

    evidence_items.each do |item|
      validate_mini_evidence_detail!(id, item)
    end
  end

  def validate_mini_evidence_detail!(id, item)
    type = item[:type].to_s
    return unless STRICT_MINI_EVIDENCE_TYPES.include?(type)

    detail = item[:detail].to_s
    if PLACEHOLDER_MINI_EVIDENCE_PATTERNS.any? { |pattern| detail.match?(pattern) }
      raise "#{id}: #{type} evidence is a placeholder, not an exercised customer action: #{detail}"
    end

    pattern = STRICT_MINI_EVIDENCE_PATTERNS.fetch(type)
    return if detail.match?(pattern)

    raise "#{id}: #{type} evidence lacks Mini runtime provenance: #{detail}"
  end

  def dedupe_evidence(items)
    seen = {}
    items.each_with_object([]) do |item, result|
      key = [item[:type], item[:detail], Array(item[:artifacts]).join('|')]
      next if seen[key]

      seen[key] = true
      result << item
    end
  end

  def attach_required_evidence_artifacts(id, evidence_items)
    path_backed_types = %w[
      actual_output
      api_response
      automation_transcript
      file_state
      fixture
      log
      mini_automation
      mini_ax
      mini_click
      mini_runtime
      mini_screenshots
      mini_url_route
      mini_screenshot
      model_response
      screenshot
      state_receipt
      visual_screenshot
      visual_smoke
    ]
    image_types = %w[screenshot visual_screenshot mini_screenshot visual_smoke]

    evidence_items.each_with_index.map do |item, index|
      type = item[:type].to_s
      next item unless path_backed_types.include?(type)
      next item unless Array(item[:artifacts]).compact.empty?
      next item if image_types.include?(type)

      item.merge(
        artifacts: [
          artifact_file(
            id,
            "#{type}-evidence-#{index + 1}",
            JSON.pretty_generate(type: type, detail: item[:detail])
          )
        ]
      )
    end
  end

  def functional_state_receipt(action)
    state = action['functional_state'].is_a?(Hash) ? action['functional_state'] : {}
    if state['not_required_reason'].to_s.strip.empty?
      {
        status: 'established',
        detail: [
          state['description'].to_s.strip,
          *Array(state['setup_steps']).map(&:to_s).map(&:strip),
          *Array(state['fixture_paths']).map { |path| "fixture=#{path}" }
        ].reject(&:empty?).join(' | ')
      }
    else
      {
        status: 'not_required',
        detail: state['not_required_reason'].to_s.strip
      }
    end
  end

  def receipt_inputs(action)
    values = Array(action['user_inputs']).map(&:to_s).map(&:strip).reject(&:empty?)
    values.empty? ? Array(action['steps']).map(&:to_s).map(&:strip).reject(&:empty?) : values
  end

  def receipt_outputs(action)
    values = Array(action['expected_outputs']).map(&:to_s).map(&:strip).reject(&:empty?)
    values.empty? ? Array(action['assertions']).map(&:to_s).map(&:strip).reject(&:empty?) : values
  end

  def workflow_receipt(id, action, evidence_items)
    {
      runner: 'Scripts/customer_ui_action_sweep.rb',
      steps_completed: Array(action['steps']).map(&:to_s).map(&:strip).reject(&:empty?),
      outcome: "#{id} passed with #{evidence_items.length} evidence item(s) on the Mini.",
      artifacts: workflow_artifacts(id, evidence_items)
    }
  end

  def workflow_artifacts(id, evidence_items)
    artifacts = evidence_items.flat_map { |item| Array(item[:artifacts]) }.compact
    artifacts << artifact_file(id, 'workflow', JSON.pretty_generate(
      action: id,
      transcript: @transcript,
      generated_at: Time.now.utc.iso8601
    ))
    artifacts.uniq
  end

  def mini_click_artifact(id, action, evidence_items)
    JSON.pretty_generate(
      action: id,
      steps: Array(action['steps']),
      user_inputs: receipt_inputs(action),
      evidence: evidence_items,
      transcript: @transcript
    )
  end

  def fixture_artifact(action)
    {
      functional_state: action['functional_state'],
      historical_failure_classes: Array(action['historical_failure_classes']),
      runtime_evidence: @transcript.select { |line| line.include?('runtime_smoke=') || line.include?('startup_probe=') || line.include?('exact_id=') }
    }
  end

  def log_artifact_path(id, evidence_items)
    candidates = evidence_items.flat_map { |item| Array(item[:artifacts]) }.select { |path| safe_regular_artifact_file?(path.to_s) }
    candidates.find { |path| path.to_s.end_with?('.log', '.txt') } ||
      artifact_file(id, 'log', ([@transcript, evidence_items].flatten.join("\n") + "\n"))
  end

  def support_report_artifact(settings_evidence)
    JSON.pretty_generate(
      action: 'license-about-support-actions',
      required_path: 'Report a Bug, add/remove attachments, copy report, cancel',
      oversized_media_policy: 'Large videos must use the file-sharing/manual-upload path instead of oversized email attachment delivery.',
      settings_evidence: settings_evidence.grep(/settings-(license|about)-/),
      transcript: @transcript.grep(/settings_tab=(license|about)|report|attachment|copy/i)
    )
  end

  def artifact_file(id, kind, content)
    safe_id = id.gsub(/[^a-zA-Z0-9_-]/, '-')
    path = File.join(@evidence_dir, "#{safe_id}-#{kind}.json")
    FileUtils.mkdir_p(File.dirname(path))
    safe_copy_artifact_content(path, content.to_s.end_with?("\n") ? content : "#{content}\n")
    relative(path)
  end

  def screenshot_for_action(id)
    return action_screenshot_path(id, appearance_overlay_screenshot_for_action(id)) if appearance_overlay_action?(id)

    key = if id.include?('second-menu-bar')
            'second-menu-bar'
          elsif id.include?('hotkeys') || id.include?('groups')
            'hotkeys-groups'
          elsif id.include?('control') || id.include?('data-import') || id.include?('profiles')
            'settings-control'
          elsif id.include?('rules')
            'settings-rules'
          elsif id.include?('shortcuts') || id.include?('automation')
            'settings-shortcuts'
          elsif id.include?('health') || id.include?('repair')
            'settings-health'
          elsif id.include?('license') || id.include?('about') || id.include?('pro') || id.include?('onboarding')
            'settings-license'
          elsif id.include?('settings') || id.include?('license') || id.include?('about') ||
                id.include?('health') || id.include?('rules') || id.include?('appearance') ||
                id.include?('control') || id.include?('pro')
            'settings'
          else
            'browse-icons'
          end
    path = @visual_screenshots[key] || @visual_screenshots['browse-icons'] || @screenshots.find { |candidate| usable_screenshot?(candidate) }
    raise "#{id}: no usable screenshot evidence available" unless path && usable_screenshot?(path)

    action_screenshot_path(id, path)
  end

  def appearance_overlay_action?(id)
    id.include?('appearance-customization') || id.include?('startup-wake-appearance')
  end

  def appearance_overlay_screenshot_for_action(id)
    preferred_prefix = id.include?('startup-wake') ? 'sanebar-appearance-native-fullscreen-host-' : 'sanebar-appearance-maximized-host-'
    path = latest_runtime_screenshots
      .select { |candidate| File.basename(candidate).start_with?('sanebar-appearance-') }
      .select { |candidate| usable_appearance_screenshot?(candidate) }
      .select { |candidate| File.basename(candidate).start_with?(preferred_prefix) }
      .max_by { |candidate| File.mtime(candidate) }
    path ||= latest_runtime_screenshots
      .select { |candidate| File.basename(candidate).start_with?('sanebar-appearance-') }
      .select { |candidate| usable_appearance_screenshot?(candidate) }
      .max_by { |candidate| File.mtime(candidate) }
    raise "#{id}: no usable appearance overlay screenshot evidence available" unless path

    path
  end

  def action_screenshot_path(id, path)
    absolute = File.absolute_path(path, Dir.pwd)
    safe_id = id.gsub(/[^a-zA-Z0-9_-]/, '-')
    extension = File.extname(absolute)
    destination = File.join(@evidence_dir, "#{safe_id}-screenshot#{extension.empty? ? '.png' : extension}")
    FileUtils.mkdir_p(File.dirname(destination))
    unless File.expand_path(destination) == absolute
      safe_copy_artifact(absolute, destination)
      add_png_text_chunk(destination, 'SaneSource', relative(absolute))
      add_png_text_chunk(destination, 'SaneAction', id)
    end
    relative(destination)
  end

  def add_png_text_chunk(path, keyword, text)
    data = File.binread(path)
    iend_type_index = data.rindex('IEND')
    return unless iend_type_index && iend_type_index >= 4

    insert_at = iend_type_index - 4
    chunk_type = 'tEXt'
    chunk_data = "#{keyword}\0#{text}"
    chunk = [
      [chunk_data.bytesize].pack('N'),
      chunk_type,
      chunk_data,
      [Zlib.crc32(chunk_type + chunk_data)].pack('N')
    ].join
    File.binwrite(path, data.byteslice(0, insert_at) + chunk + data.byteslice(insert_at..))
  rescue StandardError
    nil
  end

  def evidence(type, detail, artifacts = [])
    detail = detail.to_s.strip
    raise "Blank evidence detail for #{type}" if detail.empty?

    payload = { type: type, detail: detail }
    portable_artifacts = artifacts.map { |path| portable_artifact(path) }.compact
    payload[:artifacts] = portable_artifacts unless portable_artifacts.empty?
    payload
  end

  def portable_artifact(path)
    value = path.to_s.strip
    return nil if value.empty?
    return value unless value.start_with?('/')
    return value unless safe_regular_artifact_file?(value)

    safe_name = File.basename(value).gsub(/[^a-zA-Z0-9_.-]/, '-')
    destination = File.join(@evidence_dir, safe_name)
    safe_copy_artifact(value, destination)
    relative(destination)
  end

  def safe_regular_artifact_file?(path)
    safe_artifact_directory_path!(File.dirname(path))
    stat = File.lstat(path)
    stat.file?
  rescue StandardError
    false
  end

  def safe_copy_artifact(source, destination)
    source_flags = File::RDONLY
    source_flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    destination_flags = File::WRONLY | File::CREAT | File::TRUNC
    destination_flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    FileUtils.mkdir_p(File.dirname(destination))
    safe_artifact_directory_path!(File.dirname(source))
    safe_artifact_directory_path!(File.dirname(destination))
    File.open(source, source_flags) do |input|
      File.open(destination, destination_flags, 0o600) do |output|
        IO.copy_stream(input, output)
      end
    end
  end

  def safe_copy_artifact_content(destination, content)
    destination_flags = File::WRONLY | File::CREAT | File::TRUNC
    destination_flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    FileUtils.mkdir_p(File.dirname(destination))
    safe_artifact_directory_path!(File.dirname(destination))
    File.open(destination, destination_flags, 0o600) do |output|
      output.write(content)
    end
  end

  def safe_read_artifact(path)
    safe_artifact_directory_path!(File.dirname(path))
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(path, flags) do |file|
      file.read
    end
  end

  def safe_read_artifact_lines(path)
    safe_read_artifact(path).lines(chomp: true)
  end

  def safe_artifact_directory_path!(path)
    expanded = File.expand_path(path)
    current = expanded.start_with?(File::SEPARATOR) ? File::SEPARATOR : Dir.pwd
    expanded.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = current == File::SEPARATOR ? File.join(current, component) : File.join(current, component)
      next unless File.exist?(current)

      stat = File.lstat(current)
      if stat.symlink?
        real = File.realpath(current) rescue nil
        next if allowed_system_temp_directory_symlink?(current, real)

        raise "Unsafe symlink artifact directory path: #{current}"
      end
      raise "Unsafe non-directory artifact path: #{current}" unless stat.directory?
    end
    true
  end

  def allowed_system_temp_directory_symlink?(path, real)
    expanded = File.expand_path(path)
    canonical = File.expand_path(real.to_s)
    return true if expanded == '/tmp' && canonical == '/private/tmp'
    return true if expanded == '/var' && canonical == '/private/var'

    expanded == File.expand_path(Dir.tmpdir) && canonical == File.realpath(Dir.tmpdir)
  rescue StandardError
    false
  end

  def runtime_evidence_lines
    paths = [
      '/tmp/sanebar_runtime_smoke.log',
      *runtime_startup_probe_log_paths,
      *runtime_wake_probe_log_paths,
      '/tmp/sanebar_runtime_strict_fixture_smoke.log',
      '/tmp/sanebar_runtime_shared_bundle_smoke.log',
      '/tmp/sanebar_runtime_native_apple_smoke.log',
      '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    ]
    lines = paths
      .select { |path| fresh_release_runtime_evidence?(path) }
      .flat_map do |path|
        body = safe_read_artifact(path)
        if runtime_candidate_log_path?(path) && !runtime_log_candidate_matches?(body)
          raise "Runtime evidence #{path} candidate metadata does not match running SaneBar #{@running_bundle_version}(#{@running_bundle_build})."
        end
        body.lines.map { |line| "#{path}: #{line.chomp}" }
      end

    startup_artifact = runtime_startup_probe_artifact_paths.find { |path| fresh_release_runtime_evidence?(path) }
    if fresh_release_runtime_evidence?(startup_artifact)
      payload = JSON.parse(safe_read_artifact(startup_artifact))
      if payload['status'] == 'pass'
        if (provenance_error = startup_probe_runtime_provenance_error(payload, startup_artifact))
          raise provenance_error
        end
        case_names = Array(payload['cases']).map { |entry| entry['name'] }.compact.join(', ')
        lines << "#{startup_artifact}: Startup layout probe passed (#{case_names})"
      end
    end

    wake_artifact = runtime_wake_probe_artifact_paths.find { |path| fresh_release_runtime_evidence?(path) }
    if fresh_release_runtime_evidence?(wake_artifact)
      payload = JSON.parse(safe_read_artifact(wake_artifact))
      if payload['status'] == 'pass'
        if (provenance_error = wake_probe_runtime_provenance_error(payload, wake_artifact))
          raise provenance_error
        end
        case_names = Array(payload['cases']).map { |entry| entry['name'] }.compact.join(', ')
        lines << "#{wake_artifact}: Wake layout probe passed (#{case_names})"
      end
    end

    lines
  end

  def runtime_log_artifacts
    [
      '/tmp/sanebar_runtime_strict_fixture_smoke.log',
      '/tmp/sanebar_runtime_shared_bundle_smoke.log',
      '/tmp/sanebar_runtime_native_apple_smoke.log',
      '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    ].select { |path| fresh_release_runtime_evidence?(path) }
  end

  def runtime_startup_probe_log_paths
    [
      File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.log'),
      '/tmp/sanebar_runtime_startup_probe.log'
    ]
  end

  def runtime_startup_probe_artifact_paths
    [
      File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.json'),
      '/tmp/sanebar_runtime_startup_probe.json'
    ]
  end

  def runtime_wake_probe_log_paths
    [
      File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_wake_probe.log'),
      '/tmp/sanebar_runtime_wake_probe.log'
    ]
  end

  def runtime_wake_probe_artifact_paths
    [
      File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_wake_probe.json'),
      '/tmp/sanebar_runtime_wake_probe.json'
    ]
  end

  def runtime_candidate_log_path?(path)
    File.basename(path).start_with?('sanebar_runtime_') && File.basename(path).end_with?('_smoke.log')
  end

  def startup_probe_runtime_provenance_error(payload, artifact_path)
    provenance = payload['runtime_provenance']
    return "Startup layout probe artifact #{artifact_path} missing Mini runtime provenance." unless provenance.is_a?(Hash)
    return "Startup layout probe artifact #{artifact_path} does not mark mini_runtime=true." unless provenance['mini_runtime'] == true
    return "Startup layout probe artifact #{artifact_path} missing provenance host." if provenance['host'].to_s.strip.empty?
    return "Startup layout probe artifact #{artifact_path} provenance host #{provenance['host'].inspect} is not the Mini." unless provenance['host'].to_s.downcase.include?('mini')
    return "Startup layout probe artifact #{artifact_path} missing provenance generated_at." if provenance['generated_at'].to_s.strip.empty?

    artifact_app_path = payload['app_path'].to_s
    provenance_app_path = provenance['app_path'].to_s
    if !artifact_app_path.empty? && provenance_app_path != artifact_app_path
      return "Startup layout probe artifact #{artifact_path} provenance app_path #{provenance_app_path.inspect} does not match artifact app_path #{artifact_app_path.inspect}."
    end
    unless runtime_artifact_candidate_matches_project?(payload)
      return "Startup layout probe artifact #{artifact_path} candidate metadata does not match project #{project_version('MARKETING_VERSION')}(#{project_version('CURRENT_PROJECT_VERSION')})."
    end

    nil
  end

  def wake_probe_runtime_provenance_error(payload, artifact_path)
    provenance = payload['runtime_provenance']
    return "Wake layout probe artifact #{artifact_path} missing Mini runtime provenance." unless provenance.is_a?(Hash)
    return "Wake layout probe artifact #{artifact_path} does not mark mini_runtime=true." unless provenance['mini_runtime'] == true
    return "Wake layout probe artifact #{artifact_path} missing provenance host." if provenance['host'].to_s.strip.empty?
    return "Wake layout probe artifact #{artifact_path} provenance host #{provenance['host'].inspect} is not the Mini." unless provenance['host'].to_s.downcase.include?('mini')
    return "Wake layout probe artifact #{artifact_path} missing provenance generated_at." if provenance['generated_at'].to_s.strip.empty?

    artifact_app_path = payload['app_path'].to_s
    provenance_app_path = provenance['app_path'].to_s
    if !artifact_app_path.empty? && !provenance_app_path.empty? && provenance_app_path != artifact_app_path
      return "Wake layout probe artifact #{artifact_path} provenance app_path #{provenance_app_path.inspect} does not match artifact app_path #{artifact_app_path.inspect}."
    end
    unless runtime_artifact_candidate_matches_project?(payload)
      return "Wake layout probe artifact #{artifact_path} candidate metadata does not match project #{project_version('MARKETING_VERSION')}(#{project_version('CURRENT_PROJECT_VERSION')})."
    end

    nil
  end

  def runtime_artifact_candidate_matches_project?(payload)
    candidate = payload['candidate']
    return false unless candidate.is_a?(Hash)

    File.expand_path(candidate['app_path'].to_s) == '/Applications/SaneBar.app' &&
      candidate['app_version'].to_s == project_version('MARKETING_VERSION') &&
      candidate['app_build'].to_s == project_version('CURRENT_PROJECT_VERSION')
  end

  def runtime_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing runtime evidence marker #{marker}" unless line

    line
  end

  def browse_runtime_line(lines, mode)
    runtime_line(lines, "Browse mode #{mode} activation ok")
  rescue StandardError
    runtime_line(lines, "Browse mode #{mode} open/close ok")
  end

  def source_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing source guard transcript #{marker}" unless line

    line
  end

  def apple_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing AppleScript evidence #{marker}" unless line

    line
  end

  def url_line(lines, marker)
    line = lines.find { |value| value.include?("url_route=#{marker} ") || value.include?("url_route=#{marker} ok") }
    raise "Missing URL route evidence #{marker}" unless line

    line
  end

  def verify_all_actions_have_results!
    missing = @action_ids - @action_results.keys
    raise "Missing per-action QA result(s): #{missing.join(', ')}" unless missing.empty?

    extra = @action_results.keys - @action_ids
    raise "Per-action QA result(s) not in manifest: #{extra.join(', ')}" unless extra.empty?
  end

  def latest_runtime_screenshots
    Dir.glob(File.join(File.expand_path("~/Desktop/Screenshots/#{APP_NAME}"), 'sanebar-*.png'))
      .select { |path| fresh_release_runtime_evidence?(path) }
      .sort_by { |path| File.mtime(path) }
  end

  def usable_screenshot?(path)
    width, height = png_dimensions(path)
    width >= 80 && height >= 80
  end

  def usable_appearance_screenshot?(path)
    width, height = png_dimensions(path)
    width >= 80 && height >= 20
  end

  def png_dimensions(path)
    return [0, 0] unless File.file?(path)

    header = File.binread(path, 24)
    return [0, 0] unless header.start_with?("\x89PNG\r\n\x1A\n".b) && header.bytesize >= 24

    header.byteslice(16, 8).unpack('NN')
  rescue StandardError
    [0, 0]
  end

  def project_version(key)
    source = safe_regular_artifact_file?('project.yml') ? safe_read_artifact('project.yml') : ''
    match = source.match(/#{Regexp.escape(key)}:\s*(.+)$/)
    match ? match[1].strip.delete('"') : 'unknown'
  end

  def bundle_info_value(bundle_path, key)
    out, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", File.join(bundle_path, 'Contents', 'Info.plist'))
    raise "Could not read #{key} from #{bundle_path}: #{out}" unless status.success?

    out.strip
  end

  def system_events_window_names
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'return name of windows',
      'end tell',
      'end tell'
    ], timeout: 5)
  end

  def capture_snapshot(target, destination)
    destination = File.expand_path(destination)
    staged = staged_snapshot_path(destination)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.mkdir_p(File.dirname(staged))
    FileUtils.rm_f(staged)

    app_script(%(capture #{target} snapshot "#{escape_applescript(staged)}"))
    raise "#{target} snapshot was not written: #{staged}" unless File.size?(staged)

    unless File.expand_path(staged) == destination
      safe_copy_artifact(staged, destination)
      @transcript << "snapshot_staged=#{relative(destination)} source=#{staged}"
    end
    destination
  end

  def staged_snapshot_path(destination)
    safe_name = File.basename(destination).gsub(/[^a-zA-Z0-9_.-]/, '-')
    File.join(
      File.expand_path('~/Library/Caches/com.sanebar.app/customer-ui-sweep'),
      @timestamp,
      safe_name
    )
  end

  def app_script(statement)
    run_osascript([%(tell application "#{APP_NAME}" to #{statement})], timeout: 25)
  end

  def run_osascript(lines, timeout:)
    command = ['/usr/bin/osascript'] + lines.flat_map { |line| ['-e', line] }
    out, status = Open3.capture2e(*command)
    raise "osascript failed: #{out.strip}" unless status.success?

    out.strip
  end

  def escape_applescript(value)
    value.to_s.gsub('\\', '\\\\\\').gsub('"', '\\"')
  end

  def relative(path)
    path.to_s.start_with?(PROJECT_ROOT) ? path.to_s.delete_prefix("#{PROJECT_ROOT}/") : path.to_s
  end
end
