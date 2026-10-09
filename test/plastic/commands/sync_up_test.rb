# frozen_string_literal: true

require_relative "../../test_helper"

class SyncUpTest < Plastic::TestCase
  fixtures :legacy

  def import = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def legacy_metadata
    write("roadmaps/ship.md", "# Ship\n\n## Batches\n\n- [ ] 1 Build alpha — queued\n")
    write("store/1--alpha-service/spec.md", "# Spec\n\n## Decisions\n- D1 Keep local ownership\n")
  end

  def test_sync_up_offers_the_next_action_once_the_rows_hold_the_files
    legacy_metadata

    assert_call import, code: 0,
      out: ["imported INDEX.md: 2 intents", "next: plastic next --project global\nbecause: the rows hold every file changed by hand\n"]
  end

  def test_sync_up_imports_legacy_rulings_and_links_together
    legacy_metadata
    import

    assert_equal ["D1 Keep local ownership"], retrieval.rulings("1").map(&:text)
    assert retrieval.links("1").any? { |link| link.kind == "source" && link.to_ref == "global:51" }
  end

  def test_sync_up_imports_the_roadmap
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
