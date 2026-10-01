# encoding: UTF-8

require_relative "store_layout"
require "json"
require "date"
require "yaml"
require "fileutils"
require "timeout"
require_relative "boot_banner"
require_relative "doctor_core"
require_relative "session_ledger"
require_relative "day_summary"
require_relative "active_delivery"
require_relative "runner_core"
require_relative "runner_watch"
require_relative "version_number"

# Extracted from scripts/hook-session-start (intent 397, technique 1): the
# script's own logic lives here as an injectable entry, one small collaborator
# per section of the original top-level script, so a test can call Boot in
# process with argv/env/stdin given, instead of spawning a fresh Ruby per
# scenario. The script itself stays a thin wrapper below.
module SessionStartHook
  def self.call(argv: ARGV, env: ENV, stdin: $stdin)
    Boot.new(argv: argv, env: env, stdin: stdin).run
  end

  # Reads the stdin payload once: the session id it carries, and whether this
  # boot runs inside a spawned agent (intent 355 D9, n7/n8 B6). Any exception
  # here still boots the banner, never nothing.
  module StdinPayload
    def self.read(stdin)
      payload = parse(stdin)
      session_id = payload.is_a?(Hash) ? payload["session_id"].to_s : ""
      [session_id, subagent?(payload)]
    end

    def self.parse(stdin)
      return nil if stdin.tty?

      raw = stdin.read
      (raw && !raw.strip.empty?) ? JSON.parse(raw) : nil
    rescue
      nil
    end

    def self.subagent?(payload)
      payload.is_a?(Hash) && !!payload["agent_id"]
    rescue
      false
    end
  end

  # The one thing every boot always gets, independent of anything below it
  # that can raise (intent 36a reuses Doctor's own --core checks in-process).
  module CoreBanner
    def self.render(plastic_home:, plugin_root:)
      version = current_version(plastic_home, plugin_root)
      health = begin
        Doctor.new(plastic_home: plastic_home).run_core_checks("claude")
      rescue
        nil
      end
      [BootBanner.render(health: health, version: version), version]
    end

    def self.current_version(plastic_home, plugin_root)
      version_file = "#{plastic_home}/VERSION"
      return File.read(version_file).strip if File.exist?(version_file)
      return nil unless plugin_root && !plugin_root.empty?

      plugin_json_version(plugin_root)
    end

    def self.plugin_json_version(plugin_root)
      plugin_json_path = "#{plugin_root}/.claude-plugin/plugin.json"
      return nil unless File.exist?(plugin_json_path)

      parsed = begin
        JSON.parse(File.read(plugin_json_path))
      rescue
        {}
      end
      parsed["version"]
    end
  end

  # One `## Active` / `## Future` section parse, shared by the global
  # INDEX.md and a project's own INDEX.md.
  module IndexFile
    def self.parse(path)
      active = []
      future = []
      section = nil

      File.readlines(path).each do |line|
        section = section_for(line, section)
        next unless section.is_a?(Symbol) && line.strip.start_with?("- [")

        active << line.strip if section == :active
        future << line.strip if section == :future
      end
      [active, future]
    end

    def self.section_for(line, current)
      case line
      when /\A## Active/ then :active
      when /\A## Future/ then :future
      when /\A## / then nil
      else current
      end
    end
  end

  # Which project (if any) the current working directory belongs to, and
  # that project's own active/future lines (intent 231: home and the store
  # are two different paths).
  module CurrentProject
    def self.detect(plastic_home)
      projects_path = "#{plastic_home}/projects.yml"
      return nil unless File.exist?(projects_path)

      find_current(plastic_home, read_projects(projects_path))
    end

    def self.read_projects(projects_path)
      YAML.safe_load_file(projects_path)
    rescue
      {}
    end

    def self.find_current(plastic_home, projects)
      cwd = Dir.pwd
      (projects["projects"] || {}).each_pair do |slug, info|
        project_path = File.expand_path(info["path"])
        next unless cwd.start_with?(project_path)

        return build(plastic_home, slug, info, project_path)
      end
      nil
    end

    def self.build(plastic_home, slug, info, project_path)
      project_index = File.join(Plastic::StoreLayout.project_root(plastic_home, slug), "INDEX.md")
      active, future = File.exist?(project_index) ? IndexFile.parse(project_index) : [[], []]
      { "slug" => slug, "parent" => info["parent"], "path" => project_path, "active" => active, "future" => future }
    end
  end

  # The project (or global) banner with its active intent, the one piece of
  # intent context a live boot still carries (intent 341, G8, D4).
  module ProjectBanner
    def self.render(plastic_home:, project:, global_active:)
      project ? scoped(plastic_home, project) : global(global_active)
    end

    def self.scoped(plastic_home, project)
      slug = project["slug"]
      store = File.join(Plastic::StoreLayout.project_root(plastic_home, slug), "store").sub(Dir.home, "~")
      "Project: #{slug} | Store: #{store}/" + active_intent_suffix(project["active"])
    end

    def self.global(global_active)
      "PLASTIC — Global store loaded from ~/.plastic/" + active_intent_suffix(global_active)
    end

    def self.active_intent_suffix(active_lines)
      return "" unless active_lines.any? && active_lines.first =~ /\[([^\]]+)\].*store\/([\w-]+)\//

      intent_name, dir_name = $1, $2
      intent_id = dir_name.split("--").first
      "\nActive: [#{intent_id} — #{intent_name}] | Artifacts → store/#{dir_name}/"
    end
  end

  # Which deprecations are still live: a notice whose removal version is
  # already behind the installed one has nothing left to warn about. Only a
  # critical notice outlives its own removal.
  module DeprecationNotice
    def self.active(plastic_home:, plugin_root:, read_config:, current_version:)
      deprecations = load(plastic_home, plugin_root)
      dismissed = read_dismissed(read_config)
      installed = VersionNumber.parse(current_version)
      deprecations.select { |dep| live?(dep, installed, current_version, dismissed) }
    end

    def self.load(plastic_home, plugin_root)
      dep_file = (plugin_root && !plugin_root.empty?) ? "#{plugin_root}/deprecations.yml" : "#{plastic_home}/deprecations.yml"
      return [] unless File.exist?(dep_file)

      data = begin
        YAML.safe_load_file(dep_file)
      rescue
        {}
      end
      data["deprecations"] || []
    end

    def self.read_dismissed(read_config)
      JSON.parse(`"#{read_config}" deprecations_dismissed`.strip)
    rescue
      []
    end

    def self.live?(dep, installed, current_version, dismissed)
      return true if dep["severity"] == "critical"

      removal = VersionNumber.parse(dep["removal"])
      return false if installed && removal && removal < installed
      return true if current_version && dep["removal"] == current_version

      !dismissed.include?(dep["id"])
    end

    def self.lines(deprecations)
      return [] unless deprecations.any?

      [""] + deprecations.flat_map { |dep| lines_for(dep) }
    end

    def self.lines_for(dep)
      severity = dep["severity"] || "info"
      summary = dep["summary"] || dep["id"]
      removal = dep["removal"]
      link = dep["link"]
      return info_line(summary, removal, link) if severity == "info"

      warning_lines(severity, summary, removal, link, dep["migration_steps"] || [])
    end

    def self.info_line(summary, removal, link)
      line = "i Deprecation: #{summary}. Removed in: #{removal}."
      line += " See: #{link}" if link
      [line]
    end

    def self.warning_lines(severity, summary, removal, link, steps)
      marker = (severity == "critical") ? "!! DEPRECATION (critical)" : "! DEPRECATION (warning)"
      lines = ["#{marker}: #{summary}"]
      if steps.any?
        lines << "  Migration steps:"
        steps.each_with_index { |s, i| lines << "  #{i + 1}. #{s}" }
      end
      trail = "  Removed in: #{removal}"
      trail += " | Details: #{link}" if link
      lines << trail
    end
  end

  # Whether a previous session's update check left a notice to show.
  module UpdateNotice
    def self.read(plastic_home)
      cache_file = "#{plastic_home}/.cache/update-check.json"
      return nil unless File.exist?(cache_file)

      cache = begin
        JSON.parse(File.read(cache_file))
      rescue
        {}
      end
      return nil unless cache["updateAvailable"]

      "Plastic update available: #{cache["current"]} -> #{cache["latest"]} — run `plastic update`"
    end
  end

  # One unrecorded tick (record: false: reclaim and classify, no snapshot, no
  # record line) per intent ActiveDelivery.candidate_intent_dirs finds,
  # naming every stalled or done_unreported one in a single line (intent
  # 340a, G7b, n3, graph.md D10). A raise or a hang on any one candidate must
  # add nothing, never a partial line.
  module DeliveryWatch
    def self.line(plastic_home:, store_dir:, read_config:)
      Timeout.timeout(2) { build_line(plastic_home, store_dir, read_config) }
    rescue Exception # rubocop:disable Lint/RescueException -- any failure or timeout stays silent, never crashes boot
      nil
    end

    def self.build_line(plastic_home, store_dir, read_config)
      roots_raw = IO.popen({ "PLASTIC_HOME" => plastic_home }, [read_config, "project_roots"],
        err: File::NULL, &:read).to_s.strip
      project_roots = (roots_raw.empty? ? [] : Array(JSON.parse(roots_raw))).map { |root| File.expand_path(root.to_s) }

      attention = ActiveDelivery.candidate_intent_dirs(global_store: store_dir, project_roots: project_roots)
        .uniq.filter_map { |dir| line_for(dir) }
      attention.any? ? "PLASTIC watch: #{attention.join(", ")}" : nil
    end

    def self.line_for(dir)
      result = RunnerWatch.tick(RunnerCore.context(intent_dir: dir), record: false)
      return unless %w[stalled done_unreported].include?(result[:class])

      watch_intent_id = File.basename(dir).split("--").first
      return "#{watch_intent_id} done_unreported" unless result[:class] == "stalled"

      blocker = Array(result[:blockers]).first
      blocker ? "#{watch_intent_id} stalled (#{blocker})" : "#{watch_intent_id} stalled"
    end
  end

  # File every unclosed prior day ledger into today, oldest first, at most 3
  # per boot within a 5-second budget (intent 301, spec D9). Each day runs
  # the sibling file-session-intent in its own rescue; the boot never blocks.
  module FirstBootSweep
    def self.line(store_dir:)
      require "open3"
      require_relative "session_backfill"

      today = SessionLedger.day_id
      filed, candidates = run_candidates(store_dir, today)
      return nil unless filed.positive?

      line = "PLASTIC: filed #{filed} prior day ledger(s) into #{today}"
      remaining = candidates.size - filed
      remaining.positive? ? "#{line}, #{remaining} more wait for the next boot" : line
    rescue
      nil
    end

    def self.run_candidates(store_dir, today)
      filer = File.expand_path("../file-session-intent", __dir__)
      templates = File.expand_path("../../templates", __dir__)
      candidates = sweepable_days(store_dir, today, filer)
      filed = sweep_up_to_three(candidates, filer, templates, store_dir, today)
      [filed, candidates]
    end

    def self.sweepable_days(store_dir, today, filer)
      sweep_root = SessionLedger.sessions_root(store_dir)
      return [] unless Dir.exist?(sweep_root) && File.exist?(filer)

      Dir.children(sweep_root).select do |name|
        File.directory?(File.join(sweep_root, name)) && SessionLedger.valid_day_id?(name) &&
          name < today && !SessionBackfill.closed?(store_dir, name)
      end.sort
    end

    def self.sweep_up_to_three(candidates, filer, templates, store_dir, today)
      filed = 0
      budget_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      candidates.first(3).each do |day|
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > budget_end

        filed += 1 if sweep_one_day(filer, templates, store_dir, today, day)
      end
      filed
    end

    def self.sweep_one_day(filer, templates, store_dir, today, day)
      Timeout.timeout(5) do
        _out, _err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, filer,
          "--day", day, "--carry-to", today,
          "--store", store_dir, "--templates", templates)
        status.success? && SessionBackfill.closed?(store_dir, day)
      end
    rescue
      false
    end
  end

  # Open or join today's day ledger, create the session tmp dir, write the
  # heartbeat, and append the joined-count line plus the day summary (344 n2,
  # spec D4). Best-effort: any failure here degrades to no ledger line.
  module DayLedger
    def self.lines(plastic_home:, store_dir:, read_config:, env:, payload_session_id:)
      day = SessionLedger.day_id
      open_today(store_dir, day, read_config)

      sid = open_tmp_and_heartbeat(store_dir, env, payload_session_id)
      lines = [joined_line(store_dir, day)]
      summary = build_summary(store_dir, day, sid, plastic_home)
      lines << summary unless summary.empty?
      lines
    rescue
      []
    end

    def self.open_today(store_dir, day, read_config)
      author = `"#{read_config}" author`.strip
      author = "session" if author.empty?
      templates = File.expand_path("../../templates", __dir__)
      SessionLedger.open_day(store: store_dir, day: day, templates: templates, author: author)
    end

    def self.open_tmp_and_heartbeat(store_dir, env, payload_session_id)
      session = payload_session_id.empty? ? (env["CLAUDE_CODE_SESSION_ID"] || Process.pid.to_s) : payload_session_id
      sid = SessionLedger.short_session_id(nil, session)
      SessionLedger.ensure_tmp_root(store_dir)
      FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store_dir, sid))
      File.write(SessionLedger.heartbeat_path(store_dir, sid), "#{Time.now.utc.iso8601}\n")
      sid
    end

    def self.joined_line(store_dir, day)
      open_count, pending_count = count_checklist_states(store_dir, day)
      "PLASTIC: day ledger #{day} joined (#{open_count} open items, #{pending_count} pending)"
    end

    def self.count_checklist_states(store_dir, day)
      checklist = SessionLedger.checklist_path(store_dir, day)
      return [0, 0] unless File.exist?(checklist)

      parsed = File.readlines(checklist).filter_map { |line| SessionLedger.parse_checklist_line(line) }
      [parsed.count { |p| p[:state] == :open }, parsed.count { |p| p[:state] == :pending }]
    end

    def self.build_summary(store_dir, day, sid, plastic_home)
      DaySummary.build(store: store_dir, day: day, session: sid, home: plastic_home, now: Time.now)
    rescue
      ""
    end
  end

  # Prints the hook's JSON payload, or exits silently when there is genuinely
  # nothing to surface (no active intent, no deprecations, no update notice).
  module Emit
    def self.call(parts, core_banner)
      return exit(0) if parts.join.strip.empty?

      payload = {
        "hookSpecificOutput" => {
          "hookEventName" => "SessionStart",
          "additionalContext" => parts.join("\n")
        },
        # Intent 54: additionalContext is model-only, so the banner stays invisible to
        # the human. The top-level systemMessage channel is rendered in the user's
        # terminal (and re-fires on /clear). Reuse the same BootBanner line so the
        # visible banner and the model-facing banner cannot drift.
        "systemMessage" => core_banner
      }
      puts JSON.generate(payload)
    end
  end

  # One session-start boot: argument parsing and the fixed order the original
  # top-level script ran its sections in. Every section above is a
  # self-contained collaborator this class only sequences.
  class Boot
    def initialize(argv:, env:, stdin:)
      @index_path, @plastic_home, @mode, @plugin_root = argv
      @env = env
      @stdin = stdin
    end

    def run
      return exit(0) unless @index_path && @plastic_home && @mode

      @payload_session_id, @subagent_session = StdinPayload.read(@stdin)
      @store_dir = Plastic::StoreLayout.global_store(@plastic_home)
      @core_banner, @current_version = CoreBanner.render(plastic_home: @plastic_home, plugin_root: @plugin_root)
      parts = [@core_banner, ""]
      Emit.call(build_context(parts), @core_banner)
    end

    private

    # intent 341, G8: everything past the core banner is best-effort, wrapped
    # in one rescue so any exception anywhere in this assembly degrades the
    # whole boot to the core banner alone, never a naked crash.
    def build_context(parts)
      read_config = read_config_path
      append_banner_and_watch(parts, read_config)
      append_deprecations_and_update(parts)
      append_sweep_and_ledger(parts, read_config)
      parts
    rescue
      [@core_banner, ""]
    end

    def append_banner_and_watch(parts, read_config)
      active, _ = IndexFile.parse(@index_path)
      plastic_md = File.exist?("#{@plastic_home}/PLASTIC.md")
      append_watch(parts, read_config)
      append_banner(parts, plastic_md, CurrentProject.detect(@plastic_home), active)
    end

    def append_deprecations_and_update(parts)
      deprecations = DeprecationNotice.active(plastic_home: @plastic_home, plugin_root: @plugin_root,
        read_config: read_config_path, current_version: @current_version)
      parts.concat(DeprecationNotice.lines(deprecations)) unless @subagent_session

      update_notice = UpdateNotice.read(@plastic_home)
      parts.unshift("! #{update_notice}\n") if update_notice && !@subagent_session
    end

    def read_config_path
      (@plugin_root && !@plugin_root.empty?) ? "#{@plugin_root}/scripts/read-config" : File.expand_path("~/.plastic/scripts/read-config")
    end

    def append_watch(parts, read_config)
      return if @subagent_session

      line = DeliveryWatch.line(plastic_home: @plastic_home, store_dir: @store_dir, read_config: read_config)
      parts << line if line
    end

    def append_banner(parts, plastic_md, project, active)
      return unless plastic_md && !@subagent_session

      parts << ProjectBanner.render(plastic_home: @plastic_home, project: project, global_active: active)
    end

    def append_sweep_and_ledger(parts, read_config)
      return if @subagent_session

      sweep_line = FirstBootSweep.line(store_dir: @store_dir)
      parts << sweep_line if sweep_line
      parts.concat(DayLedger.lines(plastic_home: @plastic_home, store_dir: @store_dir, read_config: read_config,
        env: @env, payload_session_id: @payload_session_id))
    end
  end
end
