# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/doctor"

class DoctorStoreBackupsTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  def check(home, now, slug: "alpha") = Plastic::Doctor::StoreBackups.new(File.join(home, "stores", slug), slug, now:).check

  def test_a_store_with_a_done_backup_says_its_age_and_that_integrity_passed
    home = stale_home
    found = check(home, THIRTEEN_HOURS_LATER)

    assert_equal ["backups alpha:", "ok, newest 2026-01-01T10:00:00Z, 13 hours old, integrity passed", nil], found.to_a
  end

  def test_a_store_with_no_backup_says_so_and_is_no_finding
    found = check(fresh_home, SEEDED)

    assert_equal ["backups alpha:", "ok, no backup yet", nil], found.to_a
  end

  def test_a_newest_backup_marked_failed_is_a_finding_that_names_the_backup_command
    home = stale_home
    folders = Plastic::Graph::Knowledge::Backup::Folders.new(File.join(home, "stores", "alpha"))
    folders.write_report(folders.latest, status: "failed", goal: "all")
    found = check(home, THIRTEEN_HOURS_LATER)

    assert_equal ["backups alpha:", "newest backup 20260101100000 is failed; its integrity check did not pass", "plastic backup --project alpha"], found.to_a.then { |label, value, repair| [label, value, repair] }
  end

  def test_the_core_checks_carry_one_backups_check_for_each_store
    home = stale_home
    scope = Plastic::CLI::Scope.new(env: env_for(home), home: @home, slug: "alpha", directory: @home)
    labels = Plastic::Doctor::Core.new(scope, running: "0", loader: -> { "2" }, now: THIRTEEN_HOURS_LATER).checks.map(&:label)

    assert_equal %w[backups\ alpha: backups\ beta:], labels.grep(/\Abackups/).sort
  end
end
