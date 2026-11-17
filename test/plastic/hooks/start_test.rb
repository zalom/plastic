# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/start"
require_relative "../../../lib/plastic/doctor/check"

class StartTest < Plastic::TestCase
  fixtures :empty

  def call(*args, source: nil, env: { "PLASTIC_SESSION" => "s-1" }, event: {})
    plastic("hook", "start", *args, input: JSON.generate(source ? event.merge(source:) : event), env:, table: Plastic::CLI::TABLE)
  end

  def harness = store_graphs.retrieval.session(@session || "s-1").harness

  NESTED = { "CLAUDE_CODE_SESSION_ID" => "c-1", "CODEX_THREAD_ID" => "x-1" }.freeze

  def test_a_cleared_session_prints_the_recap_of_the_clear
    assert_call call(source: "clear"), code: 0, out: /\APlastic: the context was cleared\./
  end

  def opened_work(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:).work

  def printed_intent
    work = opened_work
    work.write_intent(title: "Alpha").intent_id.tap { |intent_id| work.print_intent(intent_id) }
  end

  def test_a_cleared_session_names_the_context_clear_and_the_open_intent_with_exit_0
    intent_id = printed_intent
    result = call(source: "clear")
    lines = result.out.lines(chomp: true)

    assert_equal [0, ""], [result.code, result.err]
    assert_equal "Plastic: the context was cleared. The rows below carry the state; run plastic graph resume.", lines.first
    assert_includes lines, "active: #{intent_id} Alpha (open)"
  end

  def test_a_compacted_session_prints_its_intent_and_the_last_log_lines_with_exit_0
    intent_id = printed_intent
    result = call(source: "compact")
    lines = result.out.lines(chomp: true)

    assert_equal [0, ""], [result.code, result.err]
    assert_equal ["Plastic: the session was compacted. The rows below carry the state; run plastic graph resume.", "intent: #{intent_id} Alpha"], lines.first(2)
    assert_equal "next: plastic next", lines.last
  end

  def test_an_empty_event_with_no_session_prints_the_recap_and_one_line_on_standard_error
    result = plastic("hook", "start", input: "", env: {}, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event names no session; nothing recorded\n"
  end

  def test_an_event_that_is_not_an_object_still_prints_when_a_session_is_set
    result = plastic("hook", "start", input: "[]", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event is not a JSON object; read as empty\n"
  end

  def test_bad_json_still_prints_when_a_session_is_set
    result = plastic("hook", "start", input: "{not json", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event is not a JSON object; read as empty\n"
  end

  def test_the_event_cwd_picks_the_store_over_the_process_directory
    project_dir = widgets_project

    result = plastic("hook", "start", input: JSON.generate({ cwd: project_dir }), env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session in store widgets\./
  end

  def test_a_directory_inside_a_project_picks_that_projects_store
    out = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new("{}"), out:, err: StringIO.new, home: @home, directory: widgets_project)

    Plastic::CLI.call(["hook", "start"], environment:, table: Plastic::CLI::TABLE)

    assert_match(/\APlastic: a new session in store widgets\./, out.string)
  end

  def test_start_writes_the_session_row
    call

    refute_nil store_graphs.retrieval.session("s-1")
  end

  def test_after_start_the_stores_own_databases_are_ignored
    call

    assert_includes folder.read(".gitignore"), "*.db"
  end

  def test_the_start_records_the_harness_whose_transcript_folder_the_event_names
    call(event: { transcript_path: "/u/.codex/sessions/2026/10/11/rollout.jsonl" })

    assert_equal "codex", harness
  end

  def test_a_start_no_harness_names_records_unknown
    call

    assert_equal "unknown", harness
  end

  def test_a_codex_start_inside_a_claude_code_shell_records_codex
    @session = "x-1"
    call(env: NESTED, event: { session_id: "x-1" })

    assert_equal "codex", harness
  end

  def test_a_claude_code_start_inside_a_codex_shell_records_claude_code
    @session = "c-1"
    call(env: NESTED, event: { session_id: "c-1" })

    assert_equal "claude-code", harness
  end

  def test_start_takes_no_harness_option
    assert_call call("--harness", "codex"), code: 0, err: "plastic: invalid option: --harness\nplastic hook start\n"
  end

  private

  def widgets_project
    File.join(@home, "proj").tap do |project_dir|
      FileUtils.mkdir_p([project_dir, File.join(@plastic_home, "stores", "widgets")])
      File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  widgets:\n    path: #{project_dir}\n")
    end
  end
end

class StartSessionRowTest < Plastic::TestCase
  fixtures :empty

  CLEARED = "Plastic: the context was cleared. The rows below carry the state; run plastic graph resume."
  NAMES = ["Alpha", "Beta", "intent new", "stopped after Beta"].freeze

  def claude(session) = { "CLAUDE_CODE_SESSION_ID" => session }

  def invoke(session, *argv, input: "{}") = plastic(*argv, input:, env: claude(session), table: Plastic::CLI::TABLE)

  def run_first_session
    invoke("s-1", "hook", "start", input: JSON.generate(source: "startup"))
    %w[Alpha Beta].each { |title| invoke("s-1", "intent", "new", title) }
    invoke("s-1", "session", "note", "stopped", "after", "Beta")
  end

  def clear_reply(session) = invoke(session, "hook", "start", input: JSON.generate(source: "clear"))

  def summary(result) = [result.code, result.err, result.out.lines(chomp: true).first, NAMES.select { |name| result.out.include?(name) }]

  def test_a_cleared_session_names_both_intents_the_savepoint_and_the_note
    run_first_session

    assert_equal [0, "", CLEARED, NAMES], summary(clear_reply("s-1"))
  end

  def test_a_cleared_session_records_the_claude_code_harness
    run_first_session
    clear_reply("s-1")

    assert_equal "claude-code", store_graphs.retrieval.session("s-1").harness
  end

  def test_a_cleared_second_session_names_both_intents_the_savepoint_and_the_note_after_the_first_ends
    run_first_session
    invoke("s-1", "hook", "end", input: JSON.generate(reason: "clear"))

    assert_equal [0, "", CLEARED, NAMES], summary(clear_reply("s-2"))
  end

  def test_a_cleared_second_session_records_the_claude_code_harness_and_the_end_of_the_first
    run_first_session
    invoke("s-1", "hook", "end", input: JSON.generate(reason: "clear"))
    clear_reply("s-2")

    assert_equal ["claude-code", "clear"], [store_graphs.retrieval.session("s-2").harness, store_graphs.retrieval.session("s-1").end_reason]
  end

  FIXTURES = File.expand_path("../../fixtures/hooks", __dir__)
  COMPACT_FIRST = "Plastic: the session was compacted. The rows below carry the state; run plastic graph resume."

  def held_claim(session)
    work = Plastic::Graph.open(home: @plastic_home, store: "global", session:).work
    intent = work.write_intent(title: "Alpha")
    work.add_node(intent_id: intent.intent_id, title: "Build")
    work.claim_node(intent_id: intent.intent_id, id: "n1", by: session)
    intent
  end

  %w[claude_code codex].each do |harness|
    define_method(:"test_the_#{harness}_compact_fixture_prints_the_short_recap_of_the_session_that_holds_a_claim") do
      input = File.read(File.join(FIXTURES, "#{harness}_session_start_compact.documented.json"))
      session = JSON.parse(input).fetch("session_id")
      intent = held_claim(session)
      lines = plastic("hook", "start", input:, env: { "PLASTIC_SESSION" => session }, table: Plastic::CLI::TABLE).out.lines(chomp: true)

      assert_equal [COMPACT_FIRST, "intent: #{intent.intent_id} Alpha"], lines.first(2)
      assert_equal "next: plastic graph resume", lines.last
      assert(lines.any? { |line| line.match?(/\A- \S+ - n1 #{session} claimed - - /) }, lines.inspect)
    end
  end

  def test_a_work_log_line_a_cut_short_write_left_pending_prints_after_the_compaction
    session = "s-dead"
    work = Plastic::Graph.open(home: @plastic_home, store: "global", session:).work
    intent = work.write_intent(title: "Alpha")
    work.add_ruling(intent_id: intent.intent_id, text: "kept")
    work.drain_logs
    result = plastic("hook", "start", input: JSON.generate(session_id: session, source: "compact"), env: { "PLASTIC_SESSION" => session }, table: Plastic::CLI::TABLE)

    assert(result.out.lines.any? { |line| line.include?(" ruled ") }, result.out)
  end
end

class StartDoctorTest < Plastic::TestCase
  fixtures :empty

  Check = Plastic::Doctor::Check

  PASSING = ->(_scope, _harness) { [] }
  FAILING = ->(_scope, _harness) { [Check.new("launcher:", "missing", "run plastic install --reinstall"), Check.new("hooks:", "stale", "run plastic init")] }
  BROKEN = ->(_scope, _harness) { raise "the doctor broke" }

  CLAUDE = "/u/.claude/projects/p/s-1.jsonl"

  def resume(health, source: nil, transcript_path: CLAUDE, env: {})
    out = StringIO.new
    err = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" }.merge(env),
      input: StringIO.new(JSON.generate({ source:, transcript_path: }.compact)), out:, err:, home: @home, directory: @home)
    code = Plastic::Hooks::Start.call([], environment:, health:)
    [code, out.string, err.string]
  end

  def test_a_failing_check_adds_one_line_that_names_plastic_doctor
    code, out, err = resume(FAILING)

    assert_equal [0, ""], [code, err]
    assert_equal ["Plastic: doctor found 2 failing checks; run plastic doctor."], out.lines(chomp: true).grep(/doctor/)
    assert_match(/\APlastic: a new session in store global\./, out)
  end

  def test_one_failing_check_is_named_as_one_check
    _code, out, _err = resume(->(_scope, _harness) { [Check.new("hooks:", "stale", "run plastic init")] })

    assert_equal ["Plastic: doctor found 1 failing check; run plastic doctor."], out.lines(chomp: true).grep(/doctor/)
  end

  def test_a_session_that_starts_fresh_runs_the_doctor
    _code, out, _err = resume(FAILING, source: "startup")

    assert_equal 1, out.lines.grep(/doctor found/).size
  end

  def test_a_resumed_compacted_or_cleared_session_never_runs_the_doctor
    lines = %w[resume compact clear].flat_map { |source| resume(FAILING, source:)[1].lines.grep(/doctor/) }

    assert_empty lines
  end

  def test_the_doctor_checks_the_harness_the_start_detected
    asked = []
    resume(->(_scope, harness) { asked << harness && [] }, transcript_path: "/u/.codex/sessions/r.jsonl")

    assert_equal ["codex"], asked
  end

  def test_a_fresh_start_recorded_as_unknown_names_the_session_and_plastic_doctor
    asked = []
    code, out, err = resume(->(_scope, harness) { asked << harness && [] }, transcript_path: nil)

    assert_equal [0, "", []], [code, err, asked]
    assert_equal ["Plastic: the session s-1 is recorded as unknown: its start hook found no sign of a registered harness; " \
                  "run plastic doctor --harness with one of claude-code, codex, hermes."], out.lines(chomp: true).grep(/doctor/)
  end

  def test_a_fresh_start_named_by_ai_agent_says_plastic_has_no_doctor_for_it
    _code, out, _err = resume(PASSING, transcript_path: nil, env: { "AI_AGENT" => "cursor" })

    assert_equal ["Plastic: the session s-1 is recorded as cursor, a harness Plastic has no doctor for; " \
                  "run plastic doctor --harness with one of claude-code, codex, hermes."], out.lines(chomp: true).grep(/doctor/)
  end

  def test_a_resumed_start_recorded_as_unknown_prints_no_explanation
    _code, out, _err = resume(PASSING, source: "resume", transcript_path: nil)

    assert_empty out.lines.grep(/recorded as/)
  end

  def test_every_check_passing_prints_nothing_about_doctor
    code, out, err = resume(PASSING)

    assert_equal [0, "Plastic: a new session in store global. Run plastic next before anything else.\n", ""], [code, out, err]
  end

  def test_a_doctor_that_breaks_still_prints_the_recap_and_exits_0
    code, out, err = resume(BROKEN)

    assert_equal 0, code
    assert_match(/\APlastic: a new session/, out)
    assert_equal "plastic hook: the doctor broke\n", err
  end
end

class StartDoctorMissingStoreTest < Plastic::TestCase
  def test_a_missing_store_stays_quiet_and_never_runs_the_doctor
    with_home(global: false) do |home|
      out = StringIO.new
      err = StringIO.new
      asked = []
      environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => home, "PLASTIC_SESSION" => "s-1" },
        input: StringIO.new("{}"), out:, err:, home: File.dirname(home), directory: File.dirname(home))

      code = Plastic::Hooks::Start.call([], environment:, health: ->(scope, _harness) { asked << scope && [] })

      assert_equal [0, "", "", []], [code, out.string, err.string, asked]
    end
  end
end

require_relative "../commands/installer_helper"
require_relative "../doctor/whole_home"

class StartHealthyHomeTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  def setup
    super
    whole_home
    @package = fake_package(RUNNING)
  end

  def test_an_installed_healthy_home_gives_no_doctor_line
    env = { "PLASTIC_PACKAGE_ROOT" => @package, "CLAUDE_CODE_SESSION_ID" => "s-1" }
    doctor = call("doctor", env:)
    resume = call("hook", "start", env:)

    assert_equal [0, 0, ""], [doctor.code, resume.code, resume.err]
    assert_match(/\APlastic: a new session/, resume.out)
    refute_match(/doctor/i, resume.out)
  end
end

# The session start takes a backup of the current store and of the global
# store when the newest one is older than twelve hours.
class StartBackupTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  def start(home, at: THIRTEEN_HOURS_LATER)
    event = JSON.generate(session_id: "s-1", cwd: project_path(home, "alpha"), source: "startup")
    plastic("hook", "start", env: env_for(home).merge("PLASTIC_SESSION" => "s-1"), input: event, table: Plastic::CLI::TABLE, clock: Clock.new(at))
  end

  def stale_home_with_global
    stale_home.tap do |home|
      seed_store(home, "global")
      backup_at(home, SEEDED, slug: "global")
      %w[alpha global].each { |slug| add_intent(home, slug) }
    end
  end

  def test_the_current_store_takes_a_backup_at_session_start
    home = stale_home_with_global
    start(home)

    assert_equal [nil, "session start"], backup_reasons(home, "alpha")
  end

  def test_the_global_store_takes_a_backup_at_session_start
    home = stale_home_with_global
    start(home)

    assert_equal [nil, "session start"], backup_reasons(home, "global")
  end

  def test_a_session_start_inside_twelve_hours_takes_none
    home = stale_home_with_global
    start(home, at: ELEVEN_HOURS_LATER)

    assert_equal [[nil], [nil]], [backup_reasons(home, "alpha"), backup_reasons(home, "global")]
  end

  def test_a_damaged_store_does_not_stop_the_hook_and_prints_no_error
    home = stale_home_with_global
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph", "global"), "not a database")
    result = start(home)

    assert_equal 0, result.code
  end
end
