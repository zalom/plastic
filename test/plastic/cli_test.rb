# frozen_string_literal: true

require "json"
require_relative "support/kernel"

class CliTest < Minitest::Test
  include KernelFixtures::Calls

  def setup = make_home

  def teardown = remove_home

  def test_find_picks_the_longest_command_the_words_start
    table = {"auto lock" => [], "auto lock renew" => []}

    assert_equal "auto lock renew", Plastic::CLI.find(%w[auto lock renew 7], table)
    assert_equal "auto lock", Plastic::CLI.find(%w[auto lock 7], table)
  end

  def test_find_returns_nil_for_unknown_words
    assert_nil Plastic::CLI.find(%w[nothing here], KernelFixtures::TABLE)
  end

  def test_the_stage_one_table_names_no_command
    assert_nil Plastic::CLI.find(%w[help])
  end

  def test_tool_returns_a_loaded_class
    assert_equal KernelFixtures::Draft, Plastic::CLI.tool("kernel draft", KernelFixtures::TABLE)
  end

  def test_tool_loads_the_file_the_class_names
    error = assert_raises(LoadError) { Plastic::CLI.tool("x", {"x" => ["Commands::IntentEnd", ""]}) }

    assert_includes error.message, "commands/intent_end"
  end

  def test_the_class_names_its_file
    assert_equal "commands/intent_end", Plastic::CLI.file_of("Commands::IntentEnd")
  end

  def test_unknown_words_exit_2_with_a_pointer_to_help
    call = plastic("nothing", "here", "at", "all")

    assert_equal 2, call.code
    assert_equal "plastic: no command \"nothing here\"; plastic help lists them\n", call.err
  end

  def test_no_words_asks_for_help
    call = plastic

    assert_equal 2, call.code
    assert_equal "plastic: no command \"\"; plastic help lists them\n", call.err
  end

  def test_a_missing_argument_exits_2_with_the_usage_line
    call = plastic("kernel", "two")

    assert_equal 2, call.code
    assert_equal "plastic: missing NAME\nplastic kernel two NAME\n", call.err
  end

  def test_an_unknown_project_exits_2
    call = plastic("kernel", "two", "ada", "--project", "nope")

    assert_equal 2, call.code
    assert_includes call.err, "no project named \"nope\"; this machine has global"
  end

  def test_a_known_project_runs_the_call
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "plastic"))

    assert_equal 0, plastic("kernel", "two", "ada", "--project", "plastic").code
  end

  def test_json_prints_the_result_next_and_because
    document = JSON.parse(plastic("kernel", "two", "ada", "--json").out)

    assert_equal ["hello ada"], document.dig("result", "output")
    assert_equal ["plastic kernel two ada", "greeted ada"], document.values_at("next", "because")
  end

  def test_a_refusal_in_json_prints_the_error_document
    call = plastic("kernel", "gate", "hold", "--json")
    document = JSON.parse(call.out)

    assert_equal 3, call.code
    assert_equal({"kind" => "refused", "message" => "the owner holds hold"}, document.dig("result", "error"))
  end

  def test_describe_says_what_a_tool_takes_and_writes
    description = KernelFixtures::Draft.describe("kernel draft")

    assert_equal "plastic kernel draft NAME [--dir DIR]", description.usage
    assert_equal [[:name], [], [:work]], [description.subject, description.reads, description.writes]
  end

  def test_a_class_outside_the_table_has_no_tool_name
    assert_nil KernelFixtures::Draft.tool_name
    assert_nil KernelFixtures::Draft.describe.name
  end

  def test_an_unknown_graph_is_invalid
    error = assert_raises(Plastic::Invalid) { Class.new(Plastic::CLI::Command) { writes :nowhere } }

    assert_includes error.message, "unknown graph nowhere"
  end

  def test_the_base_command_must_define_call
    command = Plastic::CLI::Command.new([], out: StringIO.new, err: StringIO.new, words: "x", environment: environment)

    assert_raises(NoMethodError) { command.call }
  end

  def test_the_current_environment_is_the_process
    current = Plastic::CLI::Command::Environment.current

    assert_equal [ENV, $stdin, Dir.home, Dir.pwd], [current.env, current.input, current.home, current.directory]
  end
end
