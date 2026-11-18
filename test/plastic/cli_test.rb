# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class CliTest < Plastic::TestCase
  def test_find_picks_the_longest_command_the_words_start
    table = { "node" => [], "node add" => [] }

    assert_equal "node add", Plastic::CLI.find(%w[node add 7], table)
    assert_equal "node", Plastic::CLI.find(%w[node 7], table)
  end

  def test_the_table_has_the_three_start_entries_and_no_top_level_auto_or_lock_entry
    start_words = Plastic::CLI::TABLE.keys.select { |name| name.split.include?("auto") || name == "intent start" }

    assert_equal [["intent start", "intent auto", "roadmap auto"], false, false],
      [start_words, Plastic::CLI::TABLE.key?("auto"), Plastic::CLI::TABLE.key?("intent lock status")]
  end

  def test_family_of_names_the_family_of_a_command_and_core_for_words_no_family_holds
    assert_equal ["intent", "core"], [Plastic::CLI.family_of("intent new"), Plastic::CLI.family_of("nothing here")]
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
    assert_equal "commands/intent/end", Plastic::CLI.file_of("Commands::Intent::End")
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
    assert_empty call.err
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

# exe/plastic's own entry: runs a shipped command, lists the shipped table,
# and names a command with no stage yet.
class BinCallTest < Plastic::TestCase
  def test_bin_call_runs_a_command_the_table_has
    call = plastic_bin("kernel", "who")

    assert_equal 0, call.code
    assert_includes call.out, "session"
    assert_equal "", call.err
  end

  def test_bin_call_names_a_command_with_no_stage_yet
    call = plastic_bin("nothing", "here")

    assert_equal 2, call.code
    assert_equal "plastic nothing here is not a command; run plastic help for the list\n", call.err
    assert_equal "", call.out
  end

  def test_bin_call_with_no_words_lists_only_the_shipped_table
    call = plastic_bin(table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal Plastic::CLI::TABLE.keys.size, Plastic::CLI::TABLE.keys.count { |words| call.out.lines.any? { |line| line.strip.split(/\s{2,}/).first == words } }
    assert_equal "", call.err
  end

  def test_bin_call_help_json_prints_the_shipped_commands_as_one_document
    call = plastic_bin("help", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(call.out)

    assert_equal [0, ""], [call.code, call.err]
    assert_equal Plastic::CLI::TABLE.keys, document.fetch("result").flat_map { |family| family.fetch("commands").map { |row| row.fetch("command") } }
    assert_nil document.fetch("next")
  end

  def test_bin_call_help_lists_the_shipped_commands
    call = plastic_bin("help", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "intent new"
    refute_includes call.out, "kernel"
  end

  def test_bin_call_help_accepts_help_flags_and_reports_unknown_commands
    flagged = plastic_bin("help", "--help", table: Plastic::CLI::TABLE)
    unknown = plastic_bin("help", "not-a-command", table: Plastic::CLI::TABLE)

    assert_equal [0, flagged.out], [flagged.code, plastic_bin("help", table: Plastic::CLI::TABLE).out]
    assert_equal [2, "plastic: no command \"not-a-command\"; plastic help lists them\n"], [unknown.code, unknown.err]
  end

  def test_bin_call_help_for_an_unknown_word_with_json_names_the_word_and_no_flag
    unknown = plastic_bin("help", "nosuch", "--json", table: Plastic::CLI::TABLE)

    assert_equal [2, "plastic: no command \"nosuch\"; plastic help lists them\n"], [unknown.code, unknown.err]
  end

  def test_bin_call_help_for_a_command_returns_its_exact_json_usage_without_a_home
    home, environment = absent_home_environment(env: {})

    code = Plastic::CLI.bin_call(%w[help sync down --json], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", document.dig("result", "output")&.first
    refute_path_exists home
  end

  def test_bin_call_command_help_returns_its_exact_json_usage_before_scope_resolution
    home, environment = absent_home_environment

    code = Plastic::CLI.bin_call(%w[sync down --help --json --project missing], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", document.dig("result", "output")&.first
    assert_equal ["", false], [environment.err.string, File.exist?(home)]
  end

  def test_bin_call_command_help_keeps_text_help_usable
    call = plastic_bin("sync", "down", "--help", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", call.out.lines.first&.chomp
  end

  def test_bin_call_help_for_a_command_keeps_text_help_usable
    call = plastic_bin("help", "sync", "down", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", call.out.lines.first&.chomp
  end

  def test_help_with_a_topic_name_prints_that_chapter
    call = plastic_bin("help", "tools", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [call.code, call.err]
    assert_equal File.read(File.expand_path("../../docs/help/tools.md", __dir__)), call.out
  end

  def test_a_command_wins_over_a_topic_of_the_same_name
    topics = Dir.mktmpdir
    File.write(File.join(topics, "status.md"), "A chapter named status\n")
    _home, environment = absent_home_environment
    code = Plastic::CLI.bin_call(%w[help status], environment:, table: Plastic::CLI::TABLE, topics:)

    assert_equal 0, code
    assert_includes environment.out.string, "plastic status"
    refute_includes environment.out.string, "A chapter named status"
  end

  private

  def absent_home_environment(env: nil)
    home = File.join(Dir.mktmpdir, "absent-home")
    environment = Plastic::CLI::Command::Environment.new(env: env || { "PLASTIC_HOME" => home }, input: StringIO.new,
      out: StringIO.new, err: StringIO.new, home:, directory: home)
    [home, environment]
  end
end
