# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/migration/list"

class MigrationListTest < Plastic::TestCase
  include PreviousStore

  CLOCK = FixedClock::Clock.new(MIGRATED_AT + 3600)

  def list(home) = plastic("migration", "list", "--store", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def down(home) = plastic("migration", "down", "--store", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def test_a_list_prints_each_ledger_row_of_the_store
    assert_call list(migrated_previous_home), code: 0,
      out: ["2026-11-19T12:00:00Z  up  #{DROP}  1 row of document_revisions and 1 row of sqlar"]
  end

  def test_a_list_names_what_a_down_would_undo_now
    assert_call list(migrated_previous_home), code: 0,
      out: ["down: would undo migration #{DROP} and put back 1 row of document_revisions and 1 row of sqlar"]
  end

  def test_a_list_after_a_down_prints_the_down_row_and_that_nothing_is_left_to_undo
    home = migrated_previous_home
    down(home)

    assert_call list(home), code: 0,
      out: ["2026-11-19T13:00:00Z  down  #{DROP}  1 row of document_revisions and 1 row of sqlar", "down: nothing to undo"]
  end

  def test_a_list_offers_no_next_command
    refute_includes list(migrated_previous_home).out, "next:"
  end

  def test_a_store_with_no_ledger_row_prints_one_line_that_says_so
    result = list(previous_home)

    assert_equal [0, ["no migration of alpha is in the ledger"]], [result.code, result.out.lines.map(&:chomp).reject { |line| line.start_with?("because:") }]
  end

  def test_a_list_writes_nothing
    home = migrated_previous_home
    before = [store_bytes(home), ledger_rows(home)]
    list(home)

    assert_equal before, [store_bytes(home), ledger_rows(home)]
  end
end
