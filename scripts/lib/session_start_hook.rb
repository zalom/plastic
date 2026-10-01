# encoding: UTF-8

require_relative "store_layout"
require "json"
require "date"
require "yaml"
require "fileutils"
require "timeout"
require "open3"
require_relative "boot_banner"
require_relative "doctor_core"
require_relative "session_ledger"
require_relative "session_backfill"
require_relative "day_summary"
require_relative "active_delivery"
require_relative "runner_core"
require_relative "runner_watch"
require_relative "read_config"
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
      health = core_health(plastic_home)
      [BootBanner.render(health: health, version: version), version]
    end

    def self.core_health(plastic_home)
      Doctor.new(plastic_home: plastic_home).run_core_checks("claude")
    rescue
      nil
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

      parsed = safe_json(plugin_json_path)
      parsed["version"]
    end

    def self.safe_json(path)
      JSON.parse(File.read(path))
    rescue
      {}
    end
  end

  # One `## Active` / `## Future` section parse, shared by the global
  # INDEX.md and a project's own INDEX.md.
  module IndexFile
    HEADER_SECTIONS = { "## Active" => :active, "## Future" => :future }.freeze

    def self.parse(path)
      sections = { active: [], future: [] }
      scan(path, sections)
      [sections[:active], sections[:future]]
    end

    def self.scan(path, sections)
      cursor = Cursor.new(nil)
      File.readlines(path).each do |line|
        cursor.advance(line)
        accumulate(sections, cursor.section, line)
      end
    end

    def self.accumulate(sections, section, line)
      return unless section.is_a?(Symbol)

      stripped = line.strip
      return unless stripped.start_with?("- [")

      sections[section] << stripped if sections.key?(section)
    end

    def self.section_for(line)
      HEADER_SECTIONS.find { |prefix, _| line.start_with?(prefix) }&.last
    end

    # Tracks which `##` section a line stream is currently inside, so the
    # same running state never needs to come back as a parameter the next
    # line's classification branches on.
    class Cursor
      attr_reader :section

      def initialize(section)
        @section = section
      end

      def advance(line)
        return unless line.start_with?("## ")

        @section = IndexFile.section_for(line)
      end
    end
  end

  # Which project (if any) the current working directory belongs to, and
  # that project's own active/future lines (intent 231: home and the store
  # are two different paths).
  module CurrentProject
    # A projects.yml entry whose path matched the current working directory.
    Match = Struct.new(:slug, :info, :project_path)

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
      match = match_for(projects["projects"] || {}, Dir.pwd)
      match ? build(plastic_home, match) : nil
    end

    def self.match_for(projects, cwd)
      projects.each_pair do |slug, info|
        project_path = File.expand_path(info["path"])
        return Match.new(slug: slug, info: info, project_path: project_path) if cwd.start_with?(project_path)
      end
      nil
    end

    def self.build(plastic_home, match)
      slug = match.slug
      project_index = File.join(Plastic::StoreLayout.project_root(plastic_home, slug), "INDEX.md")
      active, future = File.exist?(project_index) ? IndexFile.parse(project_index) : [[], []]
      { "slug" => slug, "parent" => match.info["parent"], "path" => match.project_path,
        "active" => active, "future" => future }
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
    # What a deprecation is checked against: the installed version, the
    # current release string, and the ids the owner already dismissed.
    Check = Struct.new(:installed, :current_version, :dismissed)

    def self.active(plastic_home:, plugin_root:, current_version:)
      deprecations = load(plastic_home, plugin_root)
      check = Check.new(installed: VersionNumber.parse(current_version), current_version: current_version,
        dismissed: read_dismissed)
      deprecations.select { |dep| live?(dep, check) }
    end

    def self.load(plastic_home, plugin_root)
      dep_file = deprecations_path(plastic_home, plugin_root)
      return [] unless File.exist?(dep_file)

      safe_load_yaml(dep_file)["deprecations"] || []
    end

    def self.deprecations_path(plastic_home, plugin_root)
      (plugin_root && !plugin_root.empty?) ? "#{plugin_root}/deprecations.yml" : "#{plastic_home}/deprecations.yml"
    end

    def self.safe_load_yaml(path)
      YAML.safe_load_file(path)
    rescue
      {}
    end

    def self.read_dismissed
      Array(ReadConfig.resolve("deprecations_dismissed"))
    rescue
      []
    end

    def self.live?(dep, check)
      return true if dep["severity"] == "critical"
      return false if removed_before_install?(dep, check)
      return true if removed_at_current?(dep, check)

      !check.dismissed.include?(dep["id"])
    end

    def self.removed_before_install?(dep, check)
      installed = check.installed
      removal = VersionNumber.parse(dep["removal"])
      installed && removal && removal < installed
    end

    def self.removed_at_current?(dep, check)
      current = check.current_version
      current && dep["removal"] == current
    end

    def self.lines(deprecations)
      return [] unless deprecations.any?

      [""] + deprecations.flat_map { |dep| lines_for(dep) }
    end

    def self.lines_for(dep)
      severity = dep["severity"] || "info"
      (severity == "info") ? info_line(dep) : warning_lines(dep)
    end

    def self.info_line(dep)
      link = dep["link"]
      line = "i Deprecation: #{dep["summary"] || dep["id"]}. Removed in: #{dep["removal"]}."
      [link ? "#{line} See: #{link}" : line]
    end

    def self.warning_lines(dep)
      [warning_marker(dep), *migration_lines(dep), removal_trail(dep)]
    end

    def self.warning_marker(dep)
      marker = (dep["severity"] == "critical") ? "!! DEPRECATION (critical)" : "! DEPRECATION (warning)"
      "#{marker}: #{dep["summary"] || dep["id"]}"
    end

    def self.migration_lines(dep)
      steps = dep["migration_steps"] || []
      return [] if steps.empty?

      ["  Migration steps:"] + steps.each_with_index.map { |step, position| "  #{position + 1}. #{step}" }
    end

    def self.removal_trail(dep)
      link = dep["link"]
      trail = "  Removed in: #{dep["removal"]}"
      link ? "#{trail} | Details: #{link}" : trail
    end
  end

  # Whether a previous session's update check left a notice to show.
  module UpdateNotice
    def self.read(plastic_home)
      cache = load_cache(plastic_home)
      return nil unless cache["updateAvailable"]

      "Plastic update available: #{cache["current"]} -> #{cache["latest"]} — run `plastic update`"
    end

    def self.load_cache(plastic_home)
      cache_file = "#{plastic_home}/.cache/update-check.json"
      return {} unless File.exist?(cache_file)

      JSON.parse(File.read(cache_file))
    rescue
      {}
    end
  end

  # One unrecorded tick (record: false: reclaim and classify, no snapshot, no
  # record line) per intent ActiveDelivery.candidate_intent_dirs finds,
  # naming every stalled or done_unreported one in a single line (intent
  # 340a, G7b, n3, graph.md D10). A raise or a hang on any one candidate must
  # add nothing, never a partial line.
  module DeliveryWatch
    def self.line(plastic_home:, store_dir:)
      Timeout.timeout(2) { build_line(plastic_home, store_dir) }
    rescue Exception # rubocop:disable Lint/RescueException -- any failure or timeout stays silent, never crashes boot
      nil
    end

    def self.build_line(plastic_home, store_dir)
      attention = candidates(store_dir, resolve_project_roots(plastic_home))
      attention.any? ? "PLASTIC watch: #{attention.join(", ")}" : nil
    end

    def self.resolve_project_roots(plastic_home)
      roots = ReadConfig.resolve("project_roots", ReadConfig::Options.new(plastic_home: plastic_home))
      Array(roots).map { |root| File.expand_path(root.to_s) }
    end

    def self.candidates(store_dir, project_roots)
      ActiveDelivery.candidate_intent_dirs(global_store: store_dir, project_roots: project_roots)
        .uniq.filter_map { |dir| line_for(dir) }
    end

    def self.line_for(dir)
      result = RunnerWatch.tick(RunnerCore.context(intent_dir: dir), record: false)
      state = result[:class]
      return unless %w[stalled done_unreported].include?(state)

      describe_attention(dir, state, result)
    end

    ATTENTION_LINES = {
      "stalled" => ->(intent_id, result) { stalled_line(intent_id, result) },
      "done_unreported" => ->(intent_id, _result) { "#{intent_id} done_unreported" }
    }.freeze

    def self.describe_attention(dir, state, result)
      intent_id = File.basename(dir).split("--").first
      ATTENTION_LINES.fetch(state).call(intent_id, result)
    end

    def self.stalled_line(intent_id, result)
      blocker = Array(result[:blockers]).first
      blocker ? "#{intent_id} stalled (#{blocker})" : "#{intent_id} stalled"
    end
  end

  # File every unclosed prior day ledger into today, oldest first, at most 3
  # per boot within a 5-second budget (intent 301, spec D9). Each day runs
  # the sibling file-session-intent in its own rescue; the boot never blocks.
  module FirstBootSweep
    # One sweep run's fixed inputs: the sibling script to shell out to, the
    # templates it needs, and where/when it is filing a prior day into.
    Job = Struct.new(:filer, :templates, :store_dir, :today)

    def self.line(store_dir:)
      today = SessionLedger.day_id
      filed, candidates = run_candidates(store_dir, today)
      return nil unless filed.positive?

      describe(filed, candidates, today)
    rescue
      nil
    end

    def self.describe(filed, candidates, today)
      line = "PLASTIC: filed #{filed} prior day ledger(s) into #{today}"
      remaining = candidates.size - filed
      remaining.positive? ? "#{line}, #{remaining} more wait for the next boot" : line
    end

    def self.run_candidates(store_dir, today)
      job = Job.new(filer: File.expand_path("../file-session-intent", __dir__),
        templates: File.expand_path("../../templates", __dir__), store_dir: store_dir, today: today)
      candidates = sweepable_days(job)
      [sweep_up_to_three(candidates, job), candidates]
    end

    def self.sweepable_days(job)
      sweep_root = SessionLedger.sessions_root(job.store_dir)
      return [] unless Dir.exist?(sweep_root) && File.exist?(job.filer)

      Dir.children(sweep_root).select { |name| sweepable_day?(sweep_root, name, job) }.sort
    end

    def self.sweepable_day?(sweep_root, name, job)
      File.directory?(File.join(sweep_root, name)) && SessionLedger.valid_day_id?(name) &&
        name < job.today && !SessionBackfill.closed?(job.store_dir, name)
    end

    def self.sweep_up_to_three(candidates, job)
      budget_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      candidates.first(3).count { |day| within_budget?(budget_end) && sweep_one_day(job, day) }
    end

    def self.within_budget?(budget_end)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) <= budget_end
    end

    def self.sweep_one_day(job, day)
      Timeout.timeout(5) { run_filer(job, day) }
    rescue
      false
    end

    def self.run_filer(job, day)
      store_dir = job.store_dir
      _out, _err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, job.filer,
        "--day", day, "--carry-to", job.today, "--store", store_dir, "--templates", job.templates)
      status.success? && SessionBackfill.closed?(store_dir, day)
    end
  end

  # Open or join today's day ledger, create the session tmp dir, write the
  # heartbeat, and append the joined-count line plus the day summary (344 n2,
  # spec D4). Best-effort: any failure here degrades to no ledger line.
  module DayLedger
    # What a day-ledger line needs from the boot: where the store and home
    # are, the process environment, and the session id the payload carried.
    Inputs = Struct.new(:plastic_home, :store_dir, :env, :payload_session_id)

    def self.lines(inputs)
      day = SessionLedger.day_id
      open_today(inputs.store_dir, day)
      sid = open_tmp_and_heartbeat(inputs)
      build_lines(inputs, day, sid)
    rescue
      []
    end

    def self.build_lines(inputs, day, sid)
      lines = [joined_line(inputs.store_dir, day)]
      summary = build_summary(inputs, day, sid)
      lines << summary unless summary.empty?
      lines
    end

    # ReadConfig.resolve defaults to ENV["PLASTIC_HOME"], the real global
    # config, not the hook's own plastic_home: the author setting has always
    # been a real-environment lookup here, matching the prior backtick call's
    # inherited (never overridden) PLASTIC_HOME.
    def self.open_today(store_dir, day)
      author = ReadConfig.resolve("author").to_s.strip
      author = "session" if author.empty?
      templates = File.expand_path("../../templates", __dir__)
      SessionLedger.open_day(store: store_dir, day: day, templates: templates, author: author)
    end

    def self.open_tmp_and_heartbeat(inputs)
      store_dir = inputs.store_dir
      sid = resolve_session_id(inputs)
      prepare_tmp_dir(store_dir, sid)
      sid
    end

    def self.prepare_tmp_dir(store_dir, sid)
      SessionLedger.ensure_tmp_root(store_dir)
      FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store_dir, sid))
      write_heartbeat(store_dir, sid)
    end

    def self.resolve_session_id(inputs)
      payload_session_id = inputs.payload_session_id
      session = payload_session_id.empty? ? (inputs.env["CLAUDE_CODE_SESSION_ID"] || Process.pid.to_s) : payload_session_id
      SessionLedger.short_session_id(nil, session)
    end

    def self.write_heartbeat(store_dir, sid)
      File.write(SessionLedger.heartbeat_path(store_dir, sid), "#{Time.now.utc.iso8601}\n")
    end

    def self.joined_line(store_dir, day)
      open_count, pending_count = count_checklist_states(store_dir, day)
      "PLASTIC: day ledger #{day} joined (#{open_count} open items, #{pending_count} pending)"
    end

    def self.count_checklist_states(store_dir, day)
      checklist = SessionLedger.checklist_path(store_dir, day)
      return [0, 0] unless File.exist?(checklist)

      tally = state_tally(checklist)
      [tally[:open] || 0, tally[:pending] || 0]
    end

    def self.state_tally(checklist)
      File.readlines(checklist)
        .filter_map { |line| SessionLedger.parse_checklist_line(line) }
        .map { |entry| entry[:state] }
        .tally
    end

    def self.build_summary(inputs, day, sid)
      DaySummary.build(store: inputs.store_dir, day: day, session: sid, home: inputs.plastic_home, now: Time.now)
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
  # self-contained collaborator this class only sequences. `@request` holds
  # what the hook was invoked with; `@state` holds what boot resolved from it
  # (the session id, whether this is a subagent, the store, the banner) -
  # two ivars stand in for what used to be eleven.
  class Boot
    # What the hook was invoked with: argv, the process environment, and stdin.
    Request = Struct.new(:index_path, :plastic_home, :mode, :plugin_root, :env, :stdin)
    # What this boot resolved from the request: the store, the session id,
    # whether it is a subagent boot, and the already-rendered core banner.
    State = Struct.new(:store_dir, :payload_session_id, :subagent_session, :core_banner, :current_version)

    def initialize(argv:, env:, stdin:)
      index_path, plastic_home, mode, plugin_root = argv
      @request = Request.new(index_path: index_path, plastic_home: plastic_home, mode: mode,
        plugin_root: plugin_root, env: env, stdin: stdin)
      @state = nil
    end

    def run
      return exit(0) unless @request.index_path && @request.plastic_home && @request.mode

      @state = resolve_state
      core_banner = @state.core_banner
      Emit.call(build_context([core_banner, ""]), core_banner)
    end

    private

    def resolve_state
      plastic_home = @request.plastic_home
      payload_session_id, subagent_session = StdinPayload.read(@request.stdin)
      core_banner, current_version = CoreBanner.render(plastic_home: plastic_home, plugin_root: @request.plugin_root)
      State.new(store_dir: Plastic::StoreLayout.global_store(plastic_home),
        payload_session_id: payload_session_id, subagent_session: subagent_session,
        core_banner: core_banner, current_version: current_version)
    end

    # intent 341, G8: everything past the core banner is best-effort, wrapped
    # in one rescue so any exception anywhere in this assembly degrades the
    # whole boot to the core banner alone, never a naked crash. intent 355,
    # D9: a subagent boot carries the core banner only, so it never even
    # enters this assembly.
    def build_context(parts)
      return parts if @state.subagent_session

      append_sections(parts)
      parts
    rescue
      [@state.core_banner, ""]
    end

    def append_sections(parts)
      append_banner_and_watch(parts)
      append_deprecations_and_update(parts)
      append_sweep_and_ledger(parts)
    end

    def append_banner_and_watch(parts)
      append_watch(parts)
      plastic_home = @request.plastic_home
      return unless File.exist?("#{plastic_home}/PLASTIC.md")

      active, _ = IndexFile.parse(@request.index_path)
      parts << ProjectBanner.render(plastic_home: plastic_home, project: CurrentProject.detect(plastic_home),
        global_active: active)
    end

    def append_deprecations_and_update(parts)
      plastic_home = @request.plastic_home
      deprecations = DeprecationNotice.active(plastic_home: plastic_home, plugin_root: @request.plugin_root,
        current_version: @state.current_version)
      parts.concat(DeprecationNotice.lines(deprecations))

      update_notice = UpdateNotice.read(plastic_home)
      parts.unshift("! #{update_notice}\n") if update_notice
    end

    def append_watch(parts)
      line = DeliveryWatch.line(plastic_home: @request.plastic_home, store_dir: @state.store_dir)
      parts << line if line
    end

    def append_sweep_and_ledger(parts)
      store_dir = @state.store_dir
      sweep_line = FirstBootSweep.line(store_dir: store_dir)
      parts << sweep_line if sweep_line
      inputs = DayLedger::Inputs.new(plastic_home: @request.plastic_home, store_dir: store_dir,
        env: @request.env, payload_session_id: @state.payload_session_id)
      parts.concat(DayLedger.lines(inputs))
    end
  end
end
