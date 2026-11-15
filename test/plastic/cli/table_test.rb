# frozen_string_literal: true

require_relative "../../test_helper"

class CLITableTest < Minitest::Test
  FAMILY_ORDER = %w[core intent project sync session config backup document architecture node edge graph roadmap hook].freeze
  CORE = %w[version doctor init install update rollback uninstall auto status next search].freeze

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
