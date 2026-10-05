# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/preview_sync"

class PreviewSyncTest < Plastic::TestCase
  fixtures :alpha_synced

  def preview(dry_run: true)
    run_workflow(Plastic::Workflows::PreviewSync, dry_run:, overwrite: false, merge: false)
  end

  def spec_body = retrieval.documents("1").find { |document| document.path == "spec.md" }&.body

  def test_a_dry_run_names_the_read_and_leaves_the_rows
    before = spec_body
    write("store/1--alpha/spec.md", "# Spec\n\nChanged on disk.\n")

    outcome, context = preview

    assert_equal [:done, "preview complete; the original store was not changed"], [outcome, context.printed.last]
    assert_includes context.printed, "preview: read store/1--alpha/spec.md"
    assert_equal before, spec_body
  end

  def test_a_real_run_prints_nothing_and_continues
    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, context.printed]
  end
end
