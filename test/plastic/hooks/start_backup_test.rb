# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/start"

# The session start takes a backup of the current store and of the global
# store when the newest one is older than twelve hours.
class HooksStartBackupTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  def start(home, at: THIRTEEN_HOURS_LATER)
    event = JSON.generate(session_id: "s-1", cwd: project_path(home, "alpha"), source: "startup")
    plastic("hook", "start", env: env_for(home).merge("PLASTIC_SESSION" => "s-1"), input: event, table: Plastic::CLI::TABLE, clock: Clock.new(at))
  end

  def stale_home_with_global
    stale_home.tap do |home|
      seed_store(home, "global")
      backup_at(home, SEEDED, slug: "global")
    end
  end

  def test_the_current_store_takes_a_backup_at_session_start
    home = stale_home_with_global
    start(home)

    assert_equal [nil, "session start"], backup_reasons(home, "alpha")
  end

  def test_the_global_store_takes_a_backup_at_session_start
    home = stale_home_with_global
    start(home)

    assert_equal [nil, "session start"], backup_reasons(home, "global")
  end

  def test_a_session_start_inside_twelve_hours_takes_none
    home = stale_home_with_global
    start(home, at: ELEVEN_HOURS_LATER)

    assert_equal [[nil], [nil]], [backup_reasons(home, "alpha"), backup_reasons(home, "global")]
  end

  def test_a_damaged_store_does_not_stop_the_hook_and_prints_no_error
    home = stale_home_with_global
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph", "global"), "not a database")
    result = start(home)

    assert_equal 0, result.code
  end
end
