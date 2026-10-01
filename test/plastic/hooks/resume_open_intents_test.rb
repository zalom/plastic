# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/resume"

class ResumeOpenIntentsTest < Plastic::TestCase
  fixtures :empty

  def call(input: nil, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("hook", "resume", input: input || JSON.generate({}), env:, table: Plastic::CLI::TABLE)
  end

  def intent(title) = store_graphs.work.write_intent(title:).intent_id

  def test_a_done_intent_is_left_out
    store_graphs.work.write_intent(title: "Alpha", status: "done")

    refute_includes call.out, "Alpha"
  end

  def test_an_open_intent_with_no_run_omits_the_next_line
    intent("Beta")

    refute_includes call.out, "next:"
  end

  def test_open_intents_over_the_cap_print_ten_and_a_count_of_the_rest
    12.times { |n| intent("I#{n}") }

    result = call

    assert_equal 10, result.out.scan(/^open: /).size
    assert_includes result.out, "and 2 more"
  end

  def test_parked_and_future_intents_are_left_out
    store_graphs.work.write_intent(title: "Side", status: "parked")
    store_graphs.work.write_intent(title: "Later", status: "future")

    result = call

    refute_includes result.out, "Side"
    refute_includes result.out, "Later"
  end

  def test_an_empty_event_with_no_session_prints_the_state_and_one_stderr_line
    intent("Beta")
    result = call(env: {}, input: "")

    assert_equal [0, "plastic hook: the event names no session; nothing recorded\n"], [result.code, result.err]
    assert_includes result.out, "open: 1 Beta (open)"
  end

  def test_an_event_that_is_not_an_object_still_prints_when_a_session_is_set
    result = call(input: "[]")

    assert_includes result.out, "Plastic: a new session"
    assert_equal 0, result.code
  end

  def test_bad_json_still_prints_when_a_session_is_set
    result = call(input: "{not json")

    assert_includes result.out, "Plastic: a new session"
    assert_equal 0, result.code
  end

  def test_a_directory_inside_a_project_picks_that_projects_store
    project_dir = File.join(@home, "proj")
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "widgets"))
    File.write(File.join(@plastic_home, "projects.yml"), "widgets:\n  path: #{project_dir}\n")
    out = StringIO.new
    err = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new(JSON.generate({})), out:, err:, home: @home, directory: project_dir)

    Plastic::CLI.call(["hook", "resume"], environment:, table: Plastic::CLI::TABLE)

    assert_includes out.string, "Plastic: a new session in store widgets"
  end

  def test_the_event_cwd_picks_the_store_over_the_process_directory
    project_dir = File.join(@home, "proj")
    FileUtils.mkdir_p([project_dir, File.join(@plastic_home, "stores", "widgets")])
    File.write(File.join(@plastic_home, "projects.yml"), "widgets:\n  path: #{project_dir}\n")

    assert_includes call(input: JSON.generate({ cwd: project_dir })).out, "Plastic: a new session in store widgets"
  end
end
