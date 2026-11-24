# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/console"

# plastic console opens the databases of one store, and the machine-wide plastic.db, read-only.
class ConsoleCommandTest < Plastic::TestCase
  fixtures :alpha

  READONLY = "attempt to write a readonly database"
  NAMES = %w[work knowledge retrieval plastic].freeze

  def console(*words, env: {}, input: "") = plastic("console", *words, env:, input:, table: Plastic::CLI::TABLE)

  def test_eval_prints_the_value_of_the_code_and_exits_zero
    assert_equal Plastic::TestCase::CommandHelper::Result.new("2\n", "", 0), console("--eval", "1 + 1")
  end

  def test_the_short_switch_gives_the_same_answer_as_eval
    assert_equal console("--eval", "1 + 1"), console("-e", "1 + 1")
  end

  def test_code_that_raises_prints_the_error_and_exits_one
    result = console("--eval", 'raise "boom"')

    assert_equal ["", "plastic: RuntimeError: boom\n", 1], [result.out, result.err, result.code]
  end

  def test_code_with_a_syntax_error_exits_one
    result = console("--eval", "1 +")

    assert_equal [1, true], [result.code, result.err.start_with?("plastic: SyntaxError")]
  end

  def test_with_json_the_value_prints_as_json_data
    result = console("--eval", '{ "a" => [1, nil] }', "--json")

    assert_equal [0, { "a" => [1, nil] }], [result.code, JSON.parse(result.out).dig("result", "value")]
  end

  def test_with_json_a_value_that_is_not_json_data_prints_its_inspect_text
    result = console("--eval", "1..3", "--json")

    assert_equal "1..3", JSON.parse(result.out).dig("result", "value")
  end

  def test_json_without_eval_is_refused_with_the_usage_line_and_exit_two
    result = console("--json")

    assert_equal [2, true], [result.code, result.err.include?("--json needs --eval")]
  end

  def test_eval_reads_one_table_of_each_database_by_its_name
    counts = {
      "work" => "nodes", "knowledge" => "intents", "retrieval" => "document_passages", "plastic" => "settings"
    }.to_h { |name, table| [name, console("--eval", "#{name}.execute('SELECT count(*) AS n FROM #{table}')")] }

    assert_equal [0] * 4, counts.values.map(&:code)
    assert_equal '[{"n"=>1}]', counts.fetch("knowledge").out.chomp
  end

  def test_help_lists_the_names_and_says_the_console_is_no_sandbox
    out = console("--help").out

    assert_equal NAMES, NAMES.select { |name| out.include?(name) }
    assert_includes out, "The console is no sandbox: Ruby can still write files."
  end

  def test_the_interactive_console_reads_its_input_and_prints_the_class_of_a_name
    result = console(input: "work.class\nexit\n")

    assert_equal 0, result.code
    assert_includes result.out, "SQLite3::Database"
  end

  def test_a_write_through_each_name_fails_as_read_only_and_exits_one
    codes = NAMES.map { |name| console("--eval", "#{name}.execute('CREATE TABLE probe (id INTEGER)')") }

    assert_equal [1] * 4, codes.map(&:code)
    assert_equal [true] * 4, codes.map { |result| result.err.include?(READONLY) }
  end

  def test_with_a_session_set_and_a_write_tried_every_file_keeps_its_bytes
    before = digests
    console("--eval", "work.execute('CREATE TABLE probe (id INTEGER)')", env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal before, digests
  end

  def test_a_store_missing_one_of_its_files_fails_naming_it_and_creates_nothing
    File.delete(File.join(store_root, "retrieval_graph.db"))
    before = digests
    result = console("--eval", "1")

    assert_equal [1, true, before], [result.code, result.err.include?("retrieval_graph.db"), digests]
  end

  def test_a_store_that_does_not_exist_is_refused_and_nothing_is_created
    before = digests
    result = console("--eval", "1", "--project", "nowhere")

    assert_equal [true, before], [result.code != 0, digests]
  end

  private

  def digests
    Dir.glob("**/*", File::FNM_DOTMATCH, base: @home).select { |path| File.file?(File.join(@home, path)) }
      .to_h { |path| [path, Digest::SHA256.file(File.join(@home, path)).hexdigest] }
  end
end
