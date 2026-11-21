# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/ledger"

class LedgerTest < Plastic::TestCase
  def ledger = Plastic::Installations::Ledger.new(@plastic_home)

  def test_a_row_carries_its_time_in_utc_and_no_harness_when_none_is_named
    ledger.append("2.0.3", "install")
    row = JSON.parse(File.read(File.join(@plastic_home, "versions.json")))

    assert_equal [true, %w[version action at]], [row["at"].end_with?("Z"), row.keys]
  end

  def test_the_rows_read_back_in_order_and_a_broken_or_blank_line_is_skipped
    ledger.append("2.0.2", "install")
    File.write(File.join(@plastic_home, "versions.json"), "{ broken\n\n", mode: "a")
    ledger.append("2.0.3", "update", harness: "claude")

    assert_equal [%w[2.0.2 2.0.3], "claude"], [ledger.read.map { |row| row["version"] }, ledger.read.last["harness"]]
  end

  def test_a_run_appends_a_row_for_each_harness_and_one_row_when_no_harness_synced
    ledger.append_run("2.0.3", "install", %w[claude codex])
    ledger.append_run("2.0.3", "reinstall", [])

    assert_equal [["claude", "codex", nil], %w[install install reinstall]],
      [ledger.read.map { |row| row["harness"] }, ledger.read.map { |row| row["action"] }]
  end

  def test_a_ledger_that_does_not_exist_reads_as_no_rows
    assert_empty Plastic::Installations::Ledger.new(File.join(@home, "nowhere")).read
  end
end
