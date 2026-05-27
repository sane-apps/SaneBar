# frozen_string_literal: true

class LiveZoneSmoke
  private

  def start_resource_watchdog
    return unless @watch_resources
    return if @app_pid.to_i <= 0

    reset_resource_watchdog_state
    FileUtils.rm_f(@resource_sample_path)
    puts format(
      '🫀 Resource watchdog armed: cpu<=%<cpu_limit>.1f%% for %<cpu_samples>d sample(s), rss<=%<rss_limit>.1fMB for %<rss_samples>d sample(s)',
      cpu_limit: @max_cpu_percent,
      cpu_samples: @max_cpu_breach_samples,
      rss_limit: @max_rss_mb,
      rss_samples: @max_rss_breach_samples
    )
    @resource_watchdog_thread = Thread.new do
      loop do
        break if @resource_watchdog_stop

        sample = read_process_resource_sample
        record_resource_sample(sample)
        break if resource_watchdog_failure

        sleep @resource_poll_seconds
      rescue StandardError => e
        if tolerate_process_monitor_error?(e)
          sleep @resource_poll_seconds
          next
        end
        record_resource_watchdog_failure("resource_watchdog process_monitor_failed reason=#{e.message}")
        break
      end
    end
  end

  def stop_resource_watchdog
    @resource_watchdog_stop = true
    return unless @resource_watchdog_thread

    @resource_watchdog_thread.join(2)
    @resource_watchdog_thread = nil
  end

  def reset_resource_watchdog_state
    @resource_watchdog_stop = false
    @resource_watchdog_mutex = Mutex.new
    @resource_watchdog_state = {
      sample_count: 0,
      peak_cpu: 0.0,
      peak_rss_mb: 0.0,
      total_cpu: 0.0,
      total_rss_mb: 0.0,
      process_monitor_failures: 0,
      last_sample: nil,
      cpu_breach_samples: 0,
      rss_breach_samples: 0,
      failure: nil,
      sample_path: @resource_sample_path
    }
  end

  def reset_resource_watchdog_window!
    return unless @watch_resources

    @resource_watchdog_mutex.synchronize do
      @resource_watchdog_state[:sample_count] = 0
      @resource_watchdog_state[:peak_cpu] = 0.0
      @resource_watchdog_state[:peak_rss_mb] = 0.0
      @resource_watchdog_state[:total_cpu] = 0.0
      @resource_watchdog_state[:total_rss_mb] = 0.0
      @resource_watchdog_state[:process_monitor_failures] = 0
      @resource_watchdog_state[:last_sample] = nil
      @resource_watchdog_state[:cpu_breach_samples] = 0
      @resource_watchdog_state[:rss_breach_samples] = 0
      @resource_watchdog_state[:failure] = nil
    end
  end

  def record_resource_sample(sample)
    failure = nil

    @resource_watchdog_mutex.synchronize do
      state = @resource_watchdog_state
      state[:sample_count] += 1
      state[:last_sample] = sample
      state[:peak_cpu] = [state[:peak_cpu], sample[:cpu]].max
      state[:peak_rss_mb] = [state[:peak_rss_mb], sample[:rss_mb]].max
      state[:total_cpu] += sample[:cpu]
      state[:total_rss_mb] += sample[:rss_mb]
      state[:process_monitor_failures] = 0
      state[:cpu_breach_samples] = sample[:cpu] >= @max_cpu_percent ? state[:cpu_breach_samples] + 1 : 0
      state[:rss_breach_samples] = sample[:rss_mb] >= @max_rss_mb ? state[:rss_breach_samples] + 1 : 0
      failure = resource_limit_failure(sample, state)
    end

    return unless failure

    sample_path = capture_resource_sample
    record_resource_watchdog_failure(format_resource_watchdog_failure(failure, sample, sample_path))
  end

  def resource_limit_failure(sample, state)
    if sample[:rss_mb] >= @emergency_rss_mb
      { key: 'peak_rss_exceeded', mode: 'emergency', limit: @emergency_rss_mb, samples: state[:rss_breach_samples] }
    elsif sample[:cpu] >= @emergency_cpu_percent
      { key: 'peak_cpu_exceeded', mode: 'emergency', limit: @emergency_cpu_percent, samples: state[:cpu_breach_samples] }
    elsif state[:rss_breach_samples] >= @max_rss_breach_samples
      { key: 'peak_rss_exceeded', mode: 'sustained', limit: @max_rss_mb, samples: state[:rss_breach_samples] }
    elsif state[:cpu_breach_samples] >= @max_cpu_breach_samples
      { key: 'peak_cpu_exceeded', mode: 'sustained', limit: @max_cpu_percent, samples: state[:cpu_breach_samples] }
    end
  end

  def format_resource_watchdog_failure(failure, sample, sample_path)
    current_value =
      if failure[:key] == 'peak_cpu_exceeded'
        format('%<value>.1f%%', value: sample[:cpu])
      else
        format('%<value>.1fMB', value: sample[:rss_mb])
      end
    limit_value =
      if failure[:key] == 'peak_cpu_exceeded'
        format('%<value>.1f%%', value: failure[:limit])
      else
        format('%<value>.1fMB', value: failure[:limit])
      end
    sample_label = sample_path && File.exist?(sample_path) ? sample_path : 'unavailable'
    "#{failure[:key]} mode=#{failure[:mode]} current=#{current_value} limit=#{limit_value} "\
      "sustainedSamples=#{failure[:samples]} pid=#{sample[:pid]} elapsed=#{sample[:elapsed]} sample=#{sample_label}"
  end

  def capture_resource_sample
    FileUtils.mkdir_p(File.dirname(@resource_sample_path))
    FileUtils.rm_f(@resource_sample_path)
    _out, status = Open3.capture2e(
      '/usr/bin/sample',
      @app_pid.to_s,
      RESOURCE_SAMPLE_DURATION_SECONDS.to_s,
      RESOURCE_SAMPLE_INTERVAL_MS.to_s,
      '-mayDie',
      '-file', @resource_sample_path
    )
    return @resource_sample_path if status.success? && File.exist?(@resource_sample_path) && !File.zero?(@resource_sample_path)

    nil
  rescue StandardError
    nil
  end

  def read_process_resource_sample
    output, status = Open3.capture2e(
      'ps',
      '-o', 'pid=,%cpu=,rss=,etime=,command=',
      '-p', @app_pid.to_s
    )
    raise 'process_missing' unless status.success?

    line = output.lines.map(&:strip).reject(&:empty?).last
    raise 'process_missing' if line.nil?

    pid, cpu, rss, elapsed, command = line.split(/\s+/, 5)
    raise "process_changed command=#{command}" unless matching_app_process?(command.to_s)

    {
      pid: pid.to_i,
      cpu: cpu.to_f,
      rss_kb: rss.to_i,
      rss_mb: rss.to_f / 1024.0,
      elapsed: elapsed.to_s,
      command: command.to_s
    }
  end

  def record_resource_watchdog_failure(message)
    @resource_watchdog_mutex.synchronize do
      @resource_watchdog_state[:failure] ||= message
    end
  end

  def tolerate_process_monitor_error?(error)
    return false unless error.message == 'process_missing'
    return false unless app_process_still_alive? || current_app_process_visible?

    failures = @resource_watchdog_mutex.synchronize do
      @resource_watchdog_state[:process_monitor_failures] += 1
    end
    failures < RESOURCE_WATCHDOG_PROCESS_MISSING_TOLERANCE
  end

  def app_process_still_alive?
    return false if @app_pid.to_i <= 0

    Process.kill(0, @app_pid)
    true
  rescue StandardError
    false
  end

  def current_app_process_visible?
    out, status = sh('ps ax -o pid=,command=')
    return false unless status.success?

    match = out.lines.map(&:strip).reject(&:empty?).find do |line|
      pid, command = line.split(/\s+/, 2)
      next false unless pid && command

      matching_app_process?(command.to_s)
    end
    return false unless match

    pid, = match.split(/\s+/, 2)
    @app_pid = pid.to_i if pid.to_i.positive?
    true
  rescue StandardError
    false
  end

  def resource_watchdog_failure
    return nil unless @watch_resources

    @resource_watchdog_mutex.synchronize { @resource_watchdog_state[:failure] }
  end

  def check_resource_watchdog!
    failure = resource_watchdog_failure
    raise failure if failure
  end

  def resource_watchdog_report
    state = @resource_watchdog_mutex.synchronize { @resource_watchdog_state.dup }
    return nil if state[:sample_count].zero? && state[:failure].nil?

    averages = resource_watchdog_averages(state)

    base = format(
      '🫀 Resource watchdog: samples=%<samples>d avgCpu=%<avg_cpu>.1f%% peakCpu=%<peak_cpu>.1f%% avgRss=%<avg_rss>.1fMB peakRss=%<peak_rss>.1fMB',
      samples: state[:sample_count],
      avg_cpu: averages[:avg_cpu],
      peak_cpu: state[:peak_cpu],
      avg_rss: averages[:avg_rss_mb],
      peak_rss: state[:peak_rss_mb]
    )
    return "#{base} failure=#{state[:failure]}" if state[:failure]

    base
  end

  def resource_watchdog_averages(state)
    sample_count = state[:sample_count].to_i
    return { avg_cpu: 0.0, avg_rss_mb: 0.0 } if sample_count <= 0

    {
      avg_cpu: state[:total_cpu].to_f / sample_count,
      avg_rss_mb: state[:total_rss_mb].to_f / sample_count
    }
  end

  def assert_active_average_budget!
    state = @resource_watchdog_mutex.synchronize { @resource_watchdog_state.dup }
    return if state[:sample_count].zero?
    if state[:sample_count] < DEFAULT_ACTIVE_AVG_MIN_SAMPLES
      puts format(
        'ℹ️ Active budget: skipped average check because only %<count>d sample(s) were collected; minimum=%<minimum>d',
        count: state[:sample_count],
        minimum: DEFAULT_ACTIVE_AVG_MIN_SAMPLES
      )
      return
    end

    averages = resource_watchdog_averages(state)
    failures = []
    if averages[:avg_cpu] > @active_avg_cpu_max
      failures << format('avgCpu=%<actual>.1f%% > %<limit>.1f%%', actual: averages[:avg_cpu], limit: @active_avg_cpu_max)
    end
    if averages[:avg_rss_mb] > @active_avg_rss_mb_max
      failures << format('avgRss=%<actual>.1fMB > %<limit>.1fMB', actual: averages[:avg_rss_mb], limit: @active_avg_rss_mb_max)
    end
    return if failures.empty?

    raise "active_budget_exceeded #{failures.join(' ')}"
  end

  def assert_idle_budget!(label:, settle_seconds:, sample_seconds:, cpu_avg_max:, cpu_peak_max:, rss_mb_max:)
    sleep_with_watchdog(settle_seconds) if settle_seconds.positive?
    report = capture_resource_window(sample_seconds: sample_seconds, interval_seconds: @idle_sample_interval_seconds)
    puts format(
      '📉 Idle budget %<label>s: avgCpu=%<avg_cpu>.1f%% peakCpu=%<peak_cpu>.1f%% avgRss=%<avg_rss>.1fMB peakRss=%<peak_rss>.1fMB',
      label: label,
      avg_cpu: report[:avg_cpu],
      peak_cpu: report[:peak_cpu],
      avg_rss: report[:avg_rss_mb],
      peak_rss: report[:peak_rss_mb]
    )

    failures = []
    if report[:avg_cpu] > cpu_avg_max
      failures << format('avgCpu=%<actual>.1f%% > %<limit>.1f%%', actual: report[:avg_cpu], limit: cpu_avg_max)
    end
    if report[:peak_cpu] > cpu_peak_max
      failures << format('peakCpu=%<actual>.1f%% > %<limit>.1f%%', actual: report[:peak_cpu], limit: cpu_peak_max)
    end
    peak_rss_failure = format('peakRss=%<actual>.1fMB > %<limit>.1fMB', actual: report[:peak_rss_mb], limit: rss_mb_max)
    failures << peak_rss_failure if report[:peak_rss_mb] > rss_mb_max
    if label == 'launch' &&
       failures.length == 1 &&
       failures.first.start_with?('peakCpu=') &&
       report[:avg_cpu] <= cpu_avg_max &&
       report[:peak_cpu] <= DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX
      puts format(
        'ℹ️ Idle budget %<label>s: accepting peak-only CPU spike because avgCpu=%<avg>.1f%% <= %<avg_limit>.1f%% and peakCpu=%<peak>.1f%% <= %<peak_limit>.1f%%',
        label: label,
        avg: report[:avg_cpu],
        avg_limit: cpu_avg_max,
        peak: report[:peak_cpu],
        peak_limit: DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX
      )
      return
    end
    if failures == [peak_rss_failure]
      physical_footprint_mb = current_physical_footprint_mb
      if physical_footprint_mb
        puts format(
          '🧠 Idle budget %<label>s physical footprint: %<footprint>.1fMB',
          label: label,
          footprint: physical_footprint_mb
        )
        if physical_footprint_mb <= rss_mb_max
          puts format(
            'ℹ️ Idle budget %<label>s: accepting RSS-only breach because physical footprint settled at %<footprint>.1fMB <= %<limit>.1fMB',
            label: label,
            footprint: physical_footprint_mb,
            limit: rss_mb_max
          )
          return
        end
      end
    end
    return if failures.empty?

    raise "#{label}_idle_budget_exceeded #{failures.join(' ')}"
  end

  def capture_resource_window(sample_seconds:, interval_seconds:)
    started_at = Time.now
    samples = []
    while (Time.now - started_at) < sample_seconds
      check_resource_watchdog!
      samples << read_process_resource_sample
      sleep_with_watchdog(interval_seconds)
    end

    avg_cpu = samples.sum { |sample| sample[:cpu] } / samples.length
    avg_rss_mb = samples.sum { |sample| sample[:rss_mb] } / samples.length
    {
      sample_count: samples.length,
      avg_cpu: avg_cpu,
      peak_cpu: samples.map { |sample| sample[:cpu] }.max || 0.0,
      avg_rss_mb: avg_rss_mb,
      peak_rss_mb: samples.map { |sample| sample[:rss_mb] }.max || 0.0
    }
  end

  def current_physical_footprint_mb
    output, status = Open3.capture2e(
      'footprint',
      '-p', @app_pid.to_s,
      '--format', 'formatted',
      '--noCategories'
    )
    return nil unless status.success?

    line = output.lines.find { |candidate| candidate.include?('phys_footprint:') }
    return nil unless line

    parse_memory_value_mb(line.split(':', 2).last.to_s)
  rescue StandardError
    nil
  end

  def parse_memory_value_mb(value)
    match = value.match(/([\d.]+)\s*([KMGT]?B)/i)
    return nil unless match

    magnitude = match[1].to_f
    unit = match[2].upcase
    case unit
    when 'B' then magnitude / (1024.0 * 1024.0)
    when 'KB' then magnitude / 1024.0
    when 'MB' then magnitude
    when 'GB' then magnitude * 1024.0
    when 'TB' then magnitude * 1024.0 * 1024.0
    else
      nil
    end
  end

  def sleep_with_watchdog(duration)
    deadline = Time.now + duration
    while Time.now < deadline
      check_resource_watchdog!
      remaining = deadline - Time.now
      break if remaining <= 0

      sleep([remaining, 0.1].min)
    end
    check_resource_watchdog!
  end

  def terminate_child_process(wait_thr)
    begin
      Process.kill('TERM', wait_thr.pid)
    rescue StandardError
      nil
    end
    return if wait_thr.join(1)

    begin
      Process.kill('KILL', wait_thr.pid)
    rescue StandardError
      nil
    end
    wait_thr.join
  end

  def truthy?(value)
    value == true || value.to_s.casecmp('true').zero?
  end
end
