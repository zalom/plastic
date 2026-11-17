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

    assert_equal ["backups alpha:", "ok, newest 2026-01-01T10:00:00Z, 13 hours old, integrity passed, live check 2026-01-01T10:00:00Z passed", nil], found.to_a
  end

  def test_a_store_with_no_backup_says_so_and_is_no_finding
    found = check(fresh_home, SEEDED)

    assert_equal ["backups alpha:", "ok, no backup yet", nil], found.to_a
  end

  def test_a_newest_backup_marked_failed_is_a_finding_that_names_the_backup_command
    home = stale_home
    folders = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha"))
    folders.write_report(folders.latest, status: "failed", goal: "all")
    found = check(home, THIRTEEN_HOURS_LATER)

    assert_equal ["backups alpha:", "newest backup 20260101100000 is failed; its integrity check did not pass", "plastic backup --store alpha"], found.to_a
  end

  def fill(path)
    db = SQLite3::Database.new(path)
    db.execute("CREATE TABLE filler (id INTEGER PRIMARY KEY, body TEXT)")
    db.transaction { 2000.times { |index| db.execute("INSERT INTO filler (body) VALUES (?)", ["row #{index} " * 40]) } }
    db.close
  end

  def damage_leaf(home)
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    path = store_file(home, "knowledge_graph")
    fill(path)
    File.binwrite(path, File.binread(path).tap { |bytes| bytes[bytes.bytesize - (4096 * 20) + 8, 40] = ("\xFF" * 40).b })
  end

  def test_a_failed_live_check_is_a_finding_that_names_the_file_and_the_backup_command
    home = stale_home
    damage_leaf(home)
    Plastic::Graph::Backup::Due.new(home:, slug: "alpha", now: THIRTEEN_HOURS_LATER).call("sync up")
    found = check(home, THIRTEEN_HOURS_LATER)

    assert_equal ["backups alpha:", "plastic backup --store alpha"], [found.label, found.repair]
    assert_match(/knowledge_graph\.db fails the quick check/, found.value)
  end

  def test_a_passed_live_check_is_printed_beside_the_age
    home = stale_home
    add_intent(home)
    Plastic::Graph::Backup::Due.new(home:, slug: "alpha", now: THIRTEEN_HOURS_LATER).call("sync up")
    found = check(home, THIRTEEN_HOURS_LATER)

    assert_equal "ok, newest 2026-01-01T23:00:00Z, 0 hours old, integrity passed, live check 2026-01-01T23:00:00Z passed", found.to_a[1]
  end

  def test_a_store_whose_live_check_was_never_recorded_prints_the_age_alone
    home = stale_home
    File.delete(File.join(backups_dir(home), "last-check.yml"))

    assert_equal "ok, newest 2026-01-01T10:00:00Z, 13 hours old, integrity passed", check(home, THIRTEEN_HOURS_LATER).value
  end

  def test_the_core_checks_carry_one_backups_check_for_each_store
    home = stale_home
    scope = Plastic::CLI::Scope.new(env: env_for(home), home: @home, slug: "alpha", directory: @home)
    labels = Plastic::Doctor::Core.new(scope, running: "0", loader: -> { "2" }, now: THIRTEEN_HOURS_LATER).checks.map(&:label)

    assert_equal ["backups alpha:", "backups beta:", "backups global:"], labels.grep(/\Abackups/).sort
  end
end
