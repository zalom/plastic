# encoding: UTF-8

require_relative "../store_layout"
require_relative "stdin_payload"
require_relative "core_banner"
require_relative "index_file"
require_relative "current_project"
require_relative "project_banner"
require_relative "deprecation_notice"
require_relative "update_notice"
require_relative "delivery_watch"
require_relative "first_boot_sweep"
require_relative "day_ledger"
require_relative "emit"

module SessionStartHook
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
