# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../test_helpers/beta_2_store"
require_relative "../../test_helpers/schema_versions"
require_relative "../../../lib/plastic/graph"

# A store that records a migration the code does not know, written by a run of unreleased code.
class UpdateAheadStoreTest < Plastic::TestCase
  include InstallerHelper
  include Beta2Store
  include SchemaVersions

  def ahead_store
    Plastic::Graph.create(home: @plastic_home, store: "alpha")
    Plastic::Graph::Database::ConnectionPool.release(store_root(@plastic_home))
    knowledge = store_path(@plastic_home, "knowledge_graph.db")
    SQLite3::Database.open(knowledge) { |database| database.execute_batch("PRAGMA auto_vacuum = NONE; VACUUM") }
    record_unknown_version(knowledge)
  end

  def update_ahead(version, *options)
    ahead_store
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => local_release(version) }
    call("update", *options, env:)
  end

  def test_update_downloads_the_newer_release_and_names_the_install_command
    result = update_ahead("99.0.0-alpha.2")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/^next:\s+.*install-release.*--version 99\.0\.0-alpha\.2/, result.out)
  end

  def test_update_changes_nothing_of_the_store
    ahead_store
    before = beta_2_files(@plastic_home)
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    call("update", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2") })

    assert_equal before, beta_2_files(@plastic_home)
  end

  def test_a_dry_run_names_both_versions
    result = update_ahead("99.0.0-alpha.2", "--dry-run")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/from:\s+99\.0\.0-alpha\.1/, result.out)
    assert_match(/to:\s+99\.0\.0-alpha\.2/, result.out)
  end

  def test_with_no_newer_release_update_says_the_store_came_from_unreleased_code_and_exits_1
    result = update_ahead("99.0.0-alpha.1")

    assert_equal 1, result.code
    assert_includes result.err, "unreleased code"
    assert_includes result.err, UNKNOWN
  end

  def test_every_other_command_still_refuses_with_exit_3_and_a_step_that_works
    ahead_store
    result = call("status")

    assert_equal 3, result.code
    assert_includes result.err, "is newer than this code"
    assert_includes result.err, "plastic update"
    assert_includes result.err, "unreleased code"
  end
end
