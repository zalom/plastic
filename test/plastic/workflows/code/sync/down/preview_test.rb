# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/workflows/code/sync/down/preview"

class PreviewSyncDownTest < Plastic::TestCase
  fixtures :alpha_synced

  def preview(dry_run: true)
    run_workflow(Plastic::Workflows::Code::Sync::Down::Preview, dry_run:, overwrite: false, merge: false)
  end

  def test_a_dry_run_prints_the_lines_of_the_preview_and_ends
    outcome, context = preview

    assert_equal [:done, "preview: paths that would change: 0", "preview complete; the original store was not changed"],
      [outcome, *context.printed.last(2)]
  end

  def test_a_real_run_prints_nothing_and_continues
    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, context.printed]
  end
end
