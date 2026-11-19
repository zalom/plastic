# frozen_string_literal: true

require "yaml"

# The calls that must take a backup first, and the clock they are given.
# A trigger test seeds a store whose newest backup is old, runs the call
# thirteen hours later and reads the reason the new backup folder records.
module BackupTriggers
  Clock = Struct.new(:now)

  SEEDED = Time.utc(2026, 1, 1, 10, 0, 0)
  THIRTEEN_HOURS_LATER = SEEDED + (13 * 3600)
  ELEVEN_HOURS_LATER = SEEDED + (11 * 3600)

  OLD_BACKUP = Time.new(2026, 1, 1, 7, 0, 0, "+01:00")
  DAY_STARTED = Time.new(2026, 1, 2, 0, 30, 0, "+01:00")
  LUNCHTIME = Time.new(2026, 1, 2, 13, 0, 0, "+01:00")

  # A home whose store alpha has a backup 30 hours older than LUNCHTIME and a
  # start-of-day backup taken at DAY_STARTED, and has changed since, with
  # backup.daily set as given. At LUNCHTIME its 12-hour backup is due and
  # the day already has its start-of-day backup. The test includes ConfigHomes.
  def retention_home(daily:)
    fresh_home.tap do |home|
      seed_config(home, "global:\n  backup:\n    daily: #{daily}\n")
      backup_at(home, OLD_BACKUP)
      Plastic::Graph::Backup::Day.new(File.join(home, "stores", "alpha"), "alpha", now: DAY_STARTED).begin_day
      add_intent(home)
    end
  end

  def stale_home(slug = "alpha")
    fresh_home.tap { |home| backup_at(home, SEEDED, slug:) }
  end

  def clocked_call(home, *argv, at: THIRTEEN_HOURS_LATER)
    plastic(*argv, env: env_for(home), table: Plastic::CLI::TABLE, clock: Clock.new(at))
  end

  def backup_reasons(home, slug = "alpha")
    folders = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", slug))
    folders.names.map { |name| folders.report(name)["reason"] }
  end

  def project_path(home, slug) = YAML.safe_load_file(File.join(home, "projects.yml")).fetch("projects").fetch(slug).fetch("path")
end
