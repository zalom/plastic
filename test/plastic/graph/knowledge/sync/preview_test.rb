# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncPreviewTest < Plastic::TestCase
  fixtures :alpha_synced

  SPEC = "store/1--alpha/spec.md"

  def preview(**options) = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", options).call

  def conflicting_spec
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:documents, { intent_id: "1", path: "spec.md", body: "row change", updated_at: Plastic.now })
    end
    write(SPEC, "file change")
  end

  def test_absolute_overwrite_path_is_resolved_against_original_store
    conflicting_spec
    before = snapshot(store_root)

    assert_includes preview(overwrite: store_path(SPEC)), "preview: read #{SPEC}"
    assert_equal before, snapshot(store_root)
  end

  def test_a_symbolic_link_is_rejected_before_copying
    target = File.join(@plastic_home, "outside")
    File.write(target, "keep")
    File.symlink(target, store_path("store/1--alpha/link"))
    error = assert_raises(Plastic::Invalid) { preview }

    assert_includes error.message, "symbolic link"
    assert_equal "keep", File.read(target)
  end
end
