# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphLegacyKeepTest < Plastic::TestCase
  Keep = Plastic::Graph::LegacyKeep

  def test_a_store_with_a_pending_version_that_keeps_what_it_removes_attaches_legacy_db
    assert_equal({ legacy: "/store/legacy.db" }, Keep.attachment("/store", %w[20261117000000 20261119000000]))
  end

  def test_a_store_whose_pending_versions_keep_nothing_attaches_no_legacy_db
    assert_empty Keep.attachment("/store", %w[20261117000000])
  end
end
