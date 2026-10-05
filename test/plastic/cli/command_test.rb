# frozen_string_literal: true

require_relative "../../test_helper"

class CommandTest < Plastic::TestCase
  # A command that prints the title of the intent it names, or stops the
  # way its --stop switch says.
  class Title < Plastic::CLI::Command
    STOPS = { "refuse" => Refusal, "fail" => Failure }.freeze

    argument :intent_id, label: "ID", text: "the intent"
    option :stop, switch: "--stop KIND", text: "stop with this kind"

    def call
      output.row("title:", graphs.retrieval.intent(parsed[:intent_id]).title)
      stop = STOPS[parsed[:stop]]
      raise stop, "stopped" if stop
    end
  end

  class Bare < Plastic::CLI::Command; end

  def run_tool(*argv, tool: Title, env: {})
    out = StringIO.new
    err = StringIO.new
    code = tool.new(argv, words: "title", environment: environment(out:, err:, env:)).run
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

  def test_a_failure_exits_one_with_its_line
    open_intent("Alpha")

    assert_equal ["plastic: stopped\n", 1], run_tool("1", "--stop", "fail").to_h.values_at(:err, :code)
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
end
