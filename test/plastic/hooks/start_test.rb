# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/start"

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
