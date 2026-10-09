# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/resume"

class ResumeTest < Plastic::TestCase
  fixtures :empty

  def call(source: nil, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("hook", "resume", input: JSON.generate(source ? { source: } : {}), env:, table: Plastic::CLI::TABLE)
  end

  def test_a_cleared_session_prints_the_recap_of_the_clear
    assert_call call(source: "clear"), code: 0, out: /\APlastic: the context was cleared\./
  end

  def test_an_empty_event_with_no_session_prints_the_recap_and_one_line_on_standard_error
    result = plastic("hook", "resume", input: "", env: {}, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event names no session; nothing recorded\n"
  end

  def test_an_event_that_is_not_an_object_still_prints_when_a_session_is_set
    result = plastic("hook", "resume", input: "[]", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event is not a JSON object; read as empty\n"
  end

  def test_bad_json_still_prints_when_a_session_is_set
    result = plastic("hook", "resume", input: "{not json", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session/, err: "plastic hook: the event is not a JSON object; read as empty\n"
  end

  def test_the_event_cwd_picks_the_store_over_the_process_directory
    project_dir = widgets_project

    result = plastic("hook", "resume", input: JSON.generate({ cwd: project_dir }), env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /\APlastic: a new session in store widgets\./
  end

  def test_a_directory_inside_a_project_picks_that_projects_store
    out = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new("{}"), out:, err: StringIO.new, home: @home, directory: widgets_project)

    Plastic::CLI.call(["hook", "resume"], environment:, table: Plastic::CLI::TABLE)

    assert_match(/\APlastic: a new session in store widgets\./, out.string)
  end

  def test_resume_writes_the_session_row
    call

    refute_nil store_graphs.retrieval.session("s-1")
  end

  def test_after_resume_the_stores_own_databases_are_ignored
    call

    assert_includes folder.read(".gitignore"), "*.db"
  end

  private

  def widgets_project
    File.join(@home, "proj").tap do |project_dir|
      FileUtils.mkdir_p([project_dir, File.join(@plastic_home, "stores", "widgets")])
      File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  widgets:\n    path: #{project_dir}\n")
    end
  end
end
