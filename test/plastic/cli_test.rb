# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class CliTest < Plastic::TestCase
  def test_find_picks_the_longest_command_the_words_start
    table = { "intent lock" => [], "intent lock status" => [] }

    assert_equal "intent lock status", Plastic::CLI.find(%w[intent lock status 7], table)
    assert_equal "intent lock", Plastic::CLI.find(%w[intent lock 7], table)
  end

  def test_the_table_has_one_auto_entry_and_intent_lock_status
    auto_words = Plastic::CLI::TABLE.keys.select { |name| name.split.first == "auto" }

    assert_equal [["auto"], "Commands::IntentLockStatus"], [auto_words, Plastic::CLI::TABLE.dig("intent lock status", 0)]
  end

  def test_find_returns_nil_for_unknown_words
    assert_nil Plastic::CLI.find(%w[nothing here], Fixtures::TABLE)
  end

  def test_the_stage_one_table_names_no_command
    assert_nil Plastic::CLI.find(%w[help])
  end

  def test_tool_returns_a_loaded_class
    assert_equal Fixtures::Draft, Plastic::CLI.tool("kernel draft", Fixtures::TABLE)
  end

  def test_tool_reports_the_missing_file_named_by_an_unknown_class
    error = assert_raises(LoadError) { Plastic::CLI.tool("x", { "x" => ["Commands::MissingAutoloadFixture", ""] }) }

    assert_includes error.message, "commands/missing_autoload_fixture"
  end

  def test_the_class_names_its_file
    assert_equal "commands/intent_end", Plastic::CLI.file_of("Commands::IntentEnd")
  end

  def test_unknown_words_exit_2_with_a_pointer_to_help
    call = plastic("nothing", "here", "at", "all")

    assert_equal 2, call.code
    assert_equal "plastic: no command \"nothing here\"; plastic help lists them\n", call.err
    assert_equal "", call.out
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
    assert_equal "", call.out
  end

  def test_an_unknown_project_exits_2
    call = plastic("kernel", "two", "ada", "--project", "nope")

    assert_equal 2, call.code
    assert_includes call.err, "no project named \"nope\"; this machine has global"
    assert_equal "", call.out
  end

  def test_a_known_project_runs_the_call
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "plastic"))

    call = plastic("kernel", "two", "ada", "--project", "plastic")

    assert_equal [0, "hello ada\nnext: plastic kernel two ada\nbecause: greeted ada\n", ""], [call.code, call.out, call.err]
  end

  def test_json_prints_the_result_next_and_because
    call = plastic("kernel", "two", "ada", "--json")
    document = JSON.parse(call.out)

    assert_equal [0, ""], [call.code, call.err]
    assert_equal ["hello ada"], document.dig("result", "output")
    assert_equal ["plastic kernel two ada", "greeted ada"], document.values_at("next", "because")
  end

  def test_a_refusal_in_json_prints_the_error_document
    call = plastic("kernel", "gate", "hold", "--json")
    document = JSON.parse(call.out)

    assert_equal 3, call.code
    assert_equal({ "kind" => "refused", "message" => "the owner holds hold" }, document.dig("result", "error"))
    assert_equal "plastic: refused, the owner holds hold\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n", call.err
  end

  def test_the_declarations_say_what_a_tool_takes_and_writes
    draft = Fixtures::Draft

    assert_equal "plastic kernel draft NAME [--dir DIR]", draft.usage_line("kernel draft")
    assert_equal [[:name], [], [:work]], [draft.subject, draft.reads, draft.writes]
  end

  def test_a_class_in_the_table_has_its_first_words
    assert_equal "kernel draft", Fixtures::Draft.tool_name(Fixtures::TABLE)
  end

  def test_an_optional_argument_shows_in_brackets
    optional = Class.new(Plastic::CLI::Command) { argument :id, label: "ID", text: "the intent", optional: true }

    assert_equal "plastic x [ID]", optional.usage_line("x")
  end

  def test_a_class_outside_the_table_has_no_tool_name
    assert_nil Fixtures::Draft.tool_name
  end

  def test_an_unknown_graph_is_invalid
    error = assert_raises(Plastic::Invalid) { Class.new(Plastic::CLI::Command) { writes :nowhere } }

    assert_includes error.message, "unknown graph nowhere"
  end

  def test_the_base_command_must_define_call
    command = Plastic::CLI::Command.new([], words: "x", environment: environment)

    assert_raises(NoMethodError) { command.call }
  end

  def test_the_current_environment_is_the_process
    current = Plastic::CLI::Command::Environment.current

    assert_equal [ENV, $stdin, $stdout, $stderr, Dir.home, Dir.pwd],
      [current.env, current.input, current.out, current.err, current.home, current.directory]
  end
end
