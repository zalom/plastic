# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic"
require_relative "../../support/child_process"

class CommandNamesTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  COMMANDS = File.join(ROOT, "lib", "plastic", "commands")
  FRESH_PROCESS_ENTRIES = ["backup list", "backup purge", "backup restore", "config get", "config list", "config set"].freeze

  def camel(word) = word.split("_").map(&:capitalize).join

  def entries = Plastic::CLI::TABLE.map { |words, (klass, _summary)| [words, klass] }

  def hook_entries = entries.select { |words, _klass| words.start_with?("hook ") }

  def command_entries = entries - hook_entries

  def expected_class(words) = "Commands::" + words.split.map { |word| camel(word) }.join("::")

  def expected_file(words) = File.join(COMMANDS, *words.split[0..-2], "#{words.split.last}.rb")

  def test_every_table_entry_names_the_nested_class_of_its_words
    wrong = command_entries.reject { |words, klass| klass == expected_class(words) }

    assert_empty wrong
  end

  def test_the_three_hook_entries_keep_their_hooks_classes
    assert_equal({ "hook start" => "Hooks::Start", "hook stop" => "Hooks::Stop", "hook end" => "Hooks::End" }, hook_entries.to_h)
  end

  def test_every_command_lives_in_the_file_of_its_words
    missing = command_entries.reject { |words, _klass| File.file?(expected_file(words)) }

    assert_empty missing
  end

  def test_the_cli_loads_a_class_whose_name_is_the_table_name
    wrong = entries.reject { |words, klass| Plastic::CLI.tool(words).name == "Plastic::#{klass}" }

    assert_empty wrong
  end

  def test_a_class_name_is_walked_one_segment_at_a_time_without_inherit
    source = File.read(File.join(ROOT, "lib", "plastic", "cli.rb"))

    assert_includes source, "const_get(segment, false)"
  end

  def top_level_names
    Dir.children(File.join(ROOT, "lib", "plastic")).map { |name| camel(name.delete_suffix(".rb")) }
  end

  def layout_names
    words = Plastic::CLI::TABLE.keys.flat_map(&:split).map { |word| camel(word) }
    (words + ["Hooks"]).uniq & top_level_names
  end

  def bare_receivers(path)
    code = File.read(path).lines.reject { |line| line.strip.start_with?("#") }.join
    layout_names.select { |name| code.match?(/(?<![\w:])#{name}(?=\.|::)/) }
  end

  def test_no_command_names_a_reused_top_level_constant_without_the_plastic_prefix
    found = Dir.glob(File.join(COMMANDS, "**", "*.rb")).filter_map do |path|
      names = bare_receivers(path)
      "#{path.delete_prefix("#{ROOT}/")}: #{names.join(", ")}" if names.any?
    end

    assert_empty found
  end

  def test_the_scan_knows_the_reused_names
    assert_includes layout_names, "Graph"
    assert_includes layout_names, "Config"
    assert_includes layout_names, "Doctor"
    assert_includes layout_names, "Hooks"
    assert_includes layout_names, "Context"
  end

  def parent_after(words)
    parent = words.split.first.capitalize
    code = %(require "plastic/cli"; Plastic::CLI.tool(ARGV.fetch(0)); print Plastic::Commands.const_get(ARGV.fetch(1), false).class)
    out, status = ChildProcess.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", code, words, parent, chdir: ROOT)
    [status.success?, out]
  end

  def test_a_subcommand_loaded_first_leaves_its_parent_a_class
    wrong = FRESH_PROCESS_ENTRIES.reject { |words| parent_after(words) == [true, "Class"] }

    assert_empty wrong
  end
end
