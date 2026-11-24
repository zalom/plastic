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

  # The stores folder can be entered but not listed while the block runs.
  def with_unreadable_stores(home)
    stores = File.join(home, "stores")
    File.chmod(0o333, stores)
    yield
  ensure
    File.chmod(0o755, stores)
  end

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
    call(home, "store", "backup", "--project", "alpha", "--dry-run")

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

  def test_the_start_hook_takes_its_12_hour_backup_and_then_the_start_of_day_backup
    home = daily_home
    call(home, "hook", "start", input: event(home))

    assert_equal [["session start", "start of day"], ["start of day"]], reasons(home)
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

  def test_a_daily_backup_that_cannot_list_the_stores_prints_one_line_and_the_command_goes_on
    home = daily_home
    result = with_unreadable_stores(home) { call(home, "version") }

    assert_equal 0, result.code
    assert_match(/\Abackup: the daily backups were not taken \(.+\); the call goes on\n\z/, result.err)
    refute_empty result.out
  end

  def test_a_session_end_whose_daily_backup_cannot_list_the_stores_still_records_the_end
    home = daily_home
    result = with_unreadable_stores(home) { call(home, "hook", "end", input: event(home)) }

    assert_equal 0, result.code
    assert_match(/\Abackup: the daily backups were not taken \(.+\); the call goes on\n\z/, result.err)
    refute_nil Plastic::Graph.open(home:, store: "alpha").retrieval.session("s-1").ended_at
  end

  FRIDAY_AFTERNOON = Time.new(2026, 1, 2, 16, 0, 0, "+01:00")
  FRIDAY_EVENING = Time.new(2026, 1, 2, 17, 0, 0, "+01:00")
  MONDAY_MORNING = Time.new(2026, 1, 5, 9, 0, 0, "+01:00")

  # A store whose last backups are from Friday, with nothing run since.
  def weekend_home = daily_home.tap { |home| [FRIDAY_AFTERNOON, FRIDAY_EVENING].each { |time| backup_at(home, time) } }

  def monday(home, *argv) = plastic(*argv, env: env_for(home), table: Plastic::CLI::TABLE, clock: Clock.new(MONDAY_MORNING))

  def test_a_restore_after_a_weekend_finds_the_backup_it_names
    home = weekend_home
    result = monday(home, "store", "backup", "restore", "--project", "alpha", "--timestamp", stamp(FRIDAY_AFTERNOON))

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [nil, nil, "store backup restore"], backup_reasons(home)
  end

  def test_a_backup_list_takes_no_daily_backup_and_purges_nothing
    home = weekend_home
    monday(home, "store", "backup", "list", "--project", "alpha")

    assert_equal [stamp(FRIDAY_AFTERNOON), stamp(FRIDAY_EVENING)], folder_names(home)
  end
end
