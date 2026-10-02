# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"
require_relative "../../../scripts/lib/plastic/commands/backup_list"

class BackupListTest < Plastic::TestCase
  # A real home is wrapped in a per-test transaction and rolled back, as
  # Rails rolls each test back, so a connection inside it is always mid
  # transaction. VACUUM INTO never runs inside one, so backup is proved
  # against a plain, separate home that commits as a real process would.
  def fresh_env = { "PLASTIC_HOME" => File.join(Dir.mktmpdir, ".plastic") }

  def list_call(env) = plastic("backup", "list", env:, table: Plastic::CLI::TABLE)

  def backup_path(env)
    name = plastic("backup", env:, table: Plastic::CLI::TABLE).out[/backup: (\S+),/, 1]
    File.join(env.fetch("PLASTIC_HOME"), "backups", name)
  end

  def test_a_fresh_backup_lists_clean
    env = fresh_env
    name = File.basename(backup_path(env))

    result = list_call(env)

    assert_equal 0, result.code
    assert_includes result.out, name
  end

  def test_a_removed_archive_is_flagged_missing
    env = fresh_env
    path = backup_path(env)

    File.delete(path)
    result = list_call(env)

    assert_equal 1, result.code
    assert_includes result.out, "missing"
  end

  def test_a_rewritten_archive_is_flagged_changed
    env = fresh_env
    path = backup_path(env)

    File.write(path, "not a tar file")
    result = list_call(env)

    assert_equal 1, result.code
    assert_includes result.out, "changed"
  end
end
