# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_purge"

class GraphMigrationPurgeTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 19, 13, 0, 0)

  def purge(home, version) = Plastic::Graph::MigrationPurge.new(home, "alpha", NOW).call(version)

  def test_a_purge_answers_the_rows_it_removed_by_table
    assert_equal({ "document_revisions" => 1 }, purge(migrated_previous_home, DROP).moved)
  end

  def test_a_purge_of_a_version_with_no_legacy_rows_is_refused
    error = assert_raises(Plastic::Graph::MigrationPurge::Nothing) { purge(migrated_previous_home, "20261117000000") }

    assert_equal "migration 20261117000000 keeps no rows of alpha in legacy.db, so there is nothing to purge", error.message
  end
end
