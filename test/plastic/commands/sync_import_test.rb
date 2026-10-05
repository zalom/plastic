# frozen_string_literal: true

require_relative "../../test_helper"

class SyncImportTest < Plastic::TestCase
  fixtures :legacy

  def import = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def legacy_metadata
    write("roadmaps/ship.md", "# Ship\n\n## Batches\n\n- [ ] 1 Build ai-infra — queued\n")
    write("store/1--ai-infra/spec.md", "# Spec\n\n## Decisions\n- D1 Keep local ownership\n")
  end

  def test_sync_imports_legacy_rulings_and_links_together
    legacy_metadata

    assert_equal 0, import.code
    assert_equal ["D1 Keep local ownership"], retrieval.rulings("1").map(&:text)
    assert retrieval.links("1").any? { |link| link.kind == "source" && link.to_ref == "global:51" }
  end

  def test_sync_imports_the_roadmap
    legacy_metadata
    import

    assert_equal ["1"], retrieval.roadmap_items("ship").map(&:intent_id)
  end

  def test_preview_does_not_import_the_original_store
    before = snapshot(store_root)
    result = plastic("sync", "up", "--dry-run", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: ["preview"]
    assert_equal before, snapshot(store_root)
  end
end
