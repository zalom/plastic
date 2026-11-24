# frozen_string_literal: true

require_relative "../../test_helper"

class CommandTest < Plastic::TestCase
  # A command that prints the title of the intent it names, or stops the
  # way its --stop switch says.
  class Title < Plastic::CLI::Command
    STOPS = { "refuse" => Plastic::Refused, "fail" => Plastic::Failed, "behind" => Plastic::Graph::Behind, "ahead" => Plastic::Graph::Ahead, "missing" => Plastic::Graph::MissingStore }.freeze

    argument :intent_id, label: "ID", text: "the intent"
    option :stop, switch: "--stop KIND", text: "stop with this kind"

    def call
      output.row("title:", graphs.retrieval.intent(parsed[:intent_id]).title)
      stop = STOPS[parsed[:stop]]
      raise stop, "stopped" if stop
    end
  end

  class Bare < Plastic::CLI::Command; end

  class Idle < Plastic::CLI::Command
    def call
      graphs.databases.fetch(:store).define_singleton_method(:path) { "/missing/work_graph.db" }
      graphs.work.define_singleton_method(:renew_claims) { |_session| raise "a renewal made a database" }
    end
  end

  class FailingRenewal < Plastic::CLI::Command
    argument :intent_id, label: "ID", text: "the intent"

    def call
      graphs.work.define_singleton_method(:renew_claims) { |_session| raise SQLite3::BusyException, "the database is locked" }
      output.row("title:", graphs.retrieval.intent(parsed[:intent_id]).title)
    end
  end

  class NoRenewal < Plastic::CLI::Command
    renews_no_claims

    def call
      graphs.work.define_singleton_method(:renew_claims) { |_session| raise "a renewal wrote to the work database" }
      output.row("title:", "kept")
    end
  end

  def run_tool(*argv, tool: Title, env: {})
    out = StringIO.new
    err = StringIO.new
    code = tool.new(argv, words: "title", environment: environment(out:, err:, env:)).respond
    CommandHelper::Result.new(out.string, err.string, code)
  end

  def test_a_call_prints_the_rows_it_read_from_the_store_and_exits_zero
    open_intent("Alpha")

    assert_equal CommandHelper::Result.new("title:  Alpha\n", "", 0), run_tool("1")
  end

  def test_a_missing_argument_prints_the_usage_and_exits_two
    assert_equal CommandHelper::Result.new("", "plastic: missing ID\nplastic title ID [--stop KIND]\n", 2), run_tool
  end

  def test_a_refusal_prints_the_rows_first_and_exits_three
    open_intent("Alpha")

    result = run_tool("1", "--stop", "refuse")

    assert_equal ["title:  Alpha\n", 3], [result.out, result.code]
    assert_includes result.err, "plastic: refused, stopped"
  end

  def test_a_store_ahead_of_the_code_and_a_store_behind_it_are_both_out_of_step_and_stop_with_exit_three
    open_intent("Alpha")
    codes = %w[behind ahead].map { |kind| run_tool("1", "--stop", kind).code }

    assert_equal [[3, 3], [Plastic::Graph::OutOfStep] * 2], [codes, [Plastic::Graph::Behind.superclass, Plastic::Graph::Ahead.superclass]]
  end

  def test_a_failure_exits_one_with_its_line
    open_intent("Alpha")

    assert_equal ["plastic: stopped\n", 1], run_tool("1", "--stop", "fail").to_h.values_at(:err, :code)
  end

  def test_a_database_behind_the_code_is_refused_with_exit_three
    open_intent("Alpha")
    result = run_tool("1", "--stop", "behind")

    assert_equal 3, result.code
    assert_includes result.err, "plastic: refused, stopped"
  end

  def test_a_store_that_does_not_exist_fails_with_the_project_command_to_make_it
    open_intent("Alpha")
    result = run_tool("1", "--stop", "missing")

    assert_equal 1, result.code
    assert_includes result.err, "does not exist"
  end

  def test_help_prints_the_usage_and_every_switch
    result = run_tool("--help")

    assert_equal [0, "plastic title ID [--stop KIND]"], [result.code, result.out.lines.first.chomp]
    assert_includes result.out, "--project SLUG"
  end

  def test_an_unknown_project_is_a_usage_error
    result = run_tool("1", "--project", "nowhere")

    assert_equal 2, result.code
    assert_includes result.err, "no project named \"nowhere\""
  end

  def test_json_prints_the_answer_as_one_document
    open_intent("Alpha")

    assert_equal({ "title" => "Alpha" }, JSON.parse(run_tool("1", "--json").out).fetch("result"))
  end

  def test_a_command_without_a_call_raises
    assert_raises(NoMethodError) { run_tool(tool: Bare) }
  end

  def test_a_projects_file_that_does_not_parse_fails
    open_intent("Alpha")
    File.write(File.join(@plastic_home, "projects.yml"), "- [broken")

    result = run_tool("1")

    assert_equal 1, result.code
    refute_empty result.err
  end

  def test_a_renewal_that_fails_never_changes_the_result_of_the_call
    open_intent("Alpha")
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    result = run_tool("1", tool: FailingRenewal, env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal CommandHelper::Result.new("title:  Alpha\n", "", 0), result
  end

  class BrokenRenewal < Plastic::CLI::Command
    argument :intent_id, label: "ID", text: "the intent"

    def call
      graphs.work.define_singleton_method(:renew_claims) { |_session| nil.renew }
      output.row("title:", "x")
    end
  end

  def test_a_renewal_that_is_a_bug_is_not_hidden
    open_intent("Alpha")
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    assert_raises(NoMethodError) { run_tool("1", tool: BrokenRenewal, env: { "PLASTIC_SESSION" => "s-1" }) }
  end

  def test_a_call_in_a_store_with_no_work_database_renews_nothing
    assert_equal 0, run_tool(tool: Idle, env: { "PLASTIC_SESSION" => "s-1" }).code
  end

  def test_a_command_that_renews_no_claims_leaves_the_work_database_alone_with_a_session_set
    assert_equal CommandHelper::Result.new("title:  kept\n", "", 0), run_tool(tool: NoRenewal, env: { "PLASTIC_SESSION" => "s-1" })
  end
end
