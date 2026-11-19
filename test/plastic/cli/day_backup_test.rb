# frozen_string_literal: true

require_relative "../../test_helper"

# With backup.daily on, the first call of a day, a command or a hook, takes
# the start-of-day backup of every store before its work. Help, a dry run
# and the switch off take none, and a failure prints one line and the call
# goes on.
class CLIDayBackupTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers
  include ConfigHomes

  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")

  def daily_home = fresh_home.tap { |home| seed_config(home, "global:\n  backup:\n    daily: true\n") }

  def call(home, *argv, input: "")
    plastic(*argv, env: env_for(home).merge("PLASTIC_SESSION" => "s-1"), input:, table: Plastic::CLI::TABLE, clock: Clock.new(MORNING))
  end

  def event(home) = JSON.generate(session_id: "s-1", cwd: project_path(home, "alpha"), source: "startup")

  def reasons(home) = %w[alpha beta].map { |slug| backup_reasons(home, slug) }

  def test_with_the_switch_off_a_command_takes_no_daily_backup
    home = fresh_home
    call(home, "status")

    assert_equal [[], []], reasons(home)
  end

  def test_with_the_switch_on_a_command_takes_the_start_of_day_backup_of_every_store
    home = daily_home
    call(home, "status")

    assert_equal [["start of day"], ["start of day"]], reasons(home)
  end

  def test_a_dry_run_takes_no_daily_backup
    home = daily_home
    call(home, "backup", "--store", "alpha", "--dry-run")

    assert_equal [[], []], reasons(home)
  end

  def test_help_takes_no_daily_backup
    home = daily_home
    call(home, "status", "--help")

    assert_equal [[], []], reasons(home)
  end

  def test_the_stop_hook_takes_the_start_of_day_backup
    home = daily_home
    call(home, "hook", "stop", input: event(home))

    assert_equal [["start of day"], ["start of day"]], reasons(home)
  end

  def test_the_start_hook_takes_the_start_of_day_backup
    home = daily_home
    call(home, "hook", "start", input: event(home))

    assert_equal [["start of day"], ["start of day"]], reasons(home)
  end

  def test_a_failed_backup_prints_one_line_and_the_command_goes_on
    home = daily_home
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.write(store_file(home, "work_graph"), "not a database")
    result = call(home, "status", "--project", "beta")

    assert_equal 0, result.code
    assert_match(/\Abackup: alpha was not backed up \(.+\); the call goes on\n/, result.err)
    assert_equal [["start of day"]], [backup_reasons(home, "beta")]
  end
end
