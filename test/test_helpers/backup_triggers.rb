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
