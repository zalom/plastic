# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/store/backup/restore"
require_relative "../../../../lib/plastic/commands/intent/show"

# A store built on a machine in Tokyo and restored from its backup on a machine in New York.
class BackupRestoreZoneTest < Plastic::TestCase
  include BackupHomes

  BUILT = Time.utc(2026, 10, 5, 14, 0, 0)
  LATER = Time.utc(2026, 10, 5, 15, 0, 0)

  TOKYO = "+09:00"
  NEW_YORK = "-04:00"

  # The clock of a machine, which reads the time in the zone of that machine.
  def clock(time, zone) = Struct.new(:now).new(time.getlocal(zone))

  def write(home, title, time, zone) = Plastic::Graph.open(home:, store: "alpha", clock: clock(time, zone)).work.write_intent(title:)

  def built_in_tokyo
    fresh_home.tap do |home|
      write(home, "Built", BUILT, TOKYO)
      backup_at(home, (BUILT + 60).getlocal(TOKYO))
    end
  end

  def restored_in_new_york
    built_in_tokyo.tap do |home|
      restore_call(home, "--project", "alpha", "--latest")
      write(home, "Later", LATER, NEW_YORK)
    end
  end

  def rows(home, name, sql) = SQLite3::Database.new(store_file(home, name), readonly: true).execute(sql)

  def titles(home) = rows(home, "knowledge_graph", "SELECT title FROM intents WHERE title IN ('Built', 'Later') ORDER BY updated_at").flatten

  def test_a_restored_store_keeps_its_times_in_utc
    home = restored_in_new_york
    stamps = rows(home, "knowledge_graph", "SELECT updated_at FROM intents WHERE title IN ('Built', 'Later')").flatten + rows(home, "work_graph", "SELECT at FROM work_log").flatten

    assert_equal [5, []], [stamps.size, stamps.grep_v(/Z\z/)]
  end

  def test_a_restored_store_sorts_its_times_in_the_order_they_happened
    assert_equal %w[Built Later], titles(restored_in_new_york)
  end

  def test_a_restored_store_shows_its_times_in_the_zone_of_the_machine_that_reads_them
    home = restored_in_new_york
    intent_id = rows(home, "knowledge_graph", "SELECT intent_id FROM intents WHERE title = 'Built'").flatten.first
    out = plastic("intent", "show", intent_id, "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE).out

    assert_includes out, "log: - #{shown("2026-10-05T14:00:00Z")} "
  end
end
