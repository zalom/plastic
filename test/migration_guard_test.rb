# frozen_string_literal: true

require "minitest/autorun"
require_relative "../bin/lib/migration_guard"

class MigrationGuardTest < Minitest::Test
  FOLDER = MigrationGuard::FOLDER
  BASELINE = "#{FOLDER}/store/20261117000000_store_from_beta_2.sql".freeze
  LATER = "#{FOLDER}/store/20261201000000_add_owners.sql".freeze
  HOME = "#{FOLDER}/home/20261117000000_plastic_db_from_local_db.sql".freeze

  def base = { BASELINE => "CREATE TABLE a (id INTEGER);\n", HOME => "CREATE TABLE b (id INTEGER);\n" }

  def test_a_changed_base_file_is_caught
    problems = MigrationGuard.check(base:, head: base.merge(BASELINE => "CREATE TABLE a (id TEXT);\n"))

    assert_equal ["#{BASELINE} is a merged migration and was changed, renamed or deleted; add a new migration instead"], problems
  end

  def test_a_base_file_kept_byte_for_byte_is_left_alone
    assert_empty MigrationGuard.check(base:, head: base)
  end

  def test_a_deleted_base_file_is_caught
    problems = MigrationGuard.check(base:, head: base.except(HOME))

    assert_equal ["#{HOME} is a merged migration and was changed, renamed or deleted; add a new migration instead"], problems
  end

  def test_an_added_file_that_sorts_before_the_newest_of_its_kind_at_the_base_tip_is_caught
    early = "#{FOLDER}/store/20261125000000_add_tickets.sql"
    tip = base.merge(LATER => "ALTER TABLE a ADD COLUMN owner TEXT;\n")
    problems = MigrationGuard.check(base: tip, head: tip.merge(early => "CREATE TABLE tickets (id INTEGER);\n"))

    assert_equal ["#{early} has the version 20261125000000, which is not above 20261201000000, the newest store migration on the base branch; " \
      "give it a later timestamp"], problems
  end

  def test_an_added_file_above_the_newest_of_its_kind_is_left_alone
    assert_empty MigrationGuard.check(base:, head: base.merge(LATER => "ALTER TABLE a ADD COLUMN owner TEXT;\n"))
  end

  def test_an_added_file_is_judged_against_the_newest_of_its_own_kind
    home_later = "#{FOLDER}/home/20261118000000_add_settings.sql"
    tip = base.merge(LATER => "ALTER TABLE a ADD COLUMN owner TEXT;\n")

    assert_empty MigrationGuard.check(base: tip, head: tip.merge(home_later => "CREATE TABLE settings (id INTEGER);\n"))
  end

  def test_a_base_with_no_migrations_passes_every_added_file
    assert_empty MigrationGuard.check(base: {}, head: base)
  end
end
