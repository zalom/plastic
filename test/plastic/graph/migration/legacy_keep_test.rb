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

  def test_the_drop_of_document_revisions_is_a_mistake_that_keeps_nothing_and_offers_no_undo
    assert_equal [:mistake, false, false], [Keep::KINDS.fetch("20261119000000"), Keep::KEEPS.include?("20261119000000"), Keep::WHOLE.key?("20261119000000")]
  end

  def test_a_store_with_the_cleanup_pending_attaches_legacy_db_only_when_the_file_is_there
    Dir.mktmpdir do |root|
      assert_empty Keep.attachment(root, %w[20261124150000])
      File.write(File.join(root, "legacy.db"), "")

      assert_equal({ legacy: File.join(root, "legacy.db") }, Keep.attachment(root, %w[20261124150000]))
    end
  end
end
