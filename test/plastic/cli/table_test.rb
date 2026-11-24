# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/cli"

class CLITableTest < Minitest::Test
  FAMILY_ORDER = %w[core intent project session config store resources document architecture node edge graph chat hook].freeze
  CORE = %w[version doctor init install update rollback uninstall status next search console].freeze

  def test_the_families_come_in_the_order_the_help_lists_them
    assert_equal FAMILY_ORDER, Plastic::CLI::FAMILIES.keys
  end

  def test_the_core_family_holds_the_commands_that_belong_to_no_word
    assert_equal CORE.sort, Plastic::CLI::FAMILIES.fetch("core").keys.sort
  end

  def test_every_row_of_the_table_is_in_exactly_one_family
    rows = Plastic::CLI::FAMILIES.values.flat_map(&:keys)

    assert_equal [Plastic::CLI::TABLE.keys.sort, []], [rows.sort, rows.tally.select { |_words, count| count > 1 }.keys]
  end

  def test_a_row_of_a_family_other_than_core_starts_with_the_family_word
    wrong = Plastic::CLI::FAMILIES.except("core").flat_map { |family, rows| rows.keys.reject { |words| words.split.first == family } }

    assert_empty wrong
  end

  def test_the_table_is_the_families_merged_in_order
    assert_equal Plastic::CLI::FAMILIES.values.flat_map(&:keys), Plastic::CLI::TABLE.keys
  end
end

class TableWordsTest < Plastic::TestCase
  PRINTS_A_FILE = /\bprint\w*\b[^,;:]*\b(files?|folders?)\b/i

  def test_no_help_line_says_print_for_a_file_or_a_folder
    said = Plastic::CLI::TABLE.filter_map { |words, (_, help)| words if help.match?(PRINTS_A_FILE) }

    assert_empty said
  end

  def test_the_help_of_intent_spec_names_what_it_writes_and_prints
    assert_equal "Write spec.md from a file with --from, then print the grilling method, how done criteria are written, and the open decisions of spec.md",
      Plastic::CLI::TABLE.fetch("intent spec").last
  end

  def test_the_commands_that_write_files_say_write
    assert_equal "Write the rows that changed into files", Plastic::CLI::TABLE.fetch("store sync down").last
    assert_equal "Write a future intent: its rows and its folder", Plastic::CLI::TABLE.fetch("intent new").last
  end
end

class NodeVerbNamesTest < Plastic::TestCase
  def test_the_command_table_names_ask_impede_and_resolve
    assert_equal %w[node\ ask node\ impede node\ resolve], %w[node\ ask node\ impede node\ resolve].select { |name| Plastic::CLI::TABLE.key?(name) }
  end

  def test_the_command_table_has_no_park_answer_or_flag
    assert_empty ["node park", "node answer", "node flag"].select { |name| Plastic::CLI::TABLE.key?(name) }
  end

  def test_node_states_hold_needs_info_and_impeded_and_not_parked
    assert_equal [%w[impeded needs_info], []], [%w[impeded needs_info] & Plastic::Graph::Work::Node::STATES, %w[parked flagged] & Plastic::Graph::Work::Node::STATES]
  end
end

class CLITableRoutinesTest < Minitest::Test
  def routines = Plastic::CLI::TABLE.keys.map { |words| Plastic::CLI.tool(words) }.select { |klass| klass <= Plastic::Routine }

  def problem_of(klass)
    klass.verify
    nil
  rescue Plastic::Invalid => error
    error.message
  end

  def test_the_table_holds_routines_to_verify
    refute_empty routines
  end

  def test_every_routine_of_the_table_verifies_with_no_problem
    assert_empty routines.filter_map { |klass| problem_of(klass) }
  end
end
