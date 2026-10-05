# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/preview_rollback"

class PreviewRollbackTest < Plastic::TestCase
  include InstallerHelper

  def preview(dry_run: true, target: nil)
    run_workflow(Plastic::Workflows::PreviewRollback, harness: scoped_harness(env: { "PLASTIC_SHARE" => share }), dry_run:, target:)
  end

  def test_a_dry_run_names_the_switch_to_the_previous_release
    activated("2.0.2", "2.0.3")

    outcome, context = preview

    assert_equal :done, outcome
    assert_equal [["active:", "2.0.3"], ["to:", "2.0.2"], ["releases:", "2.0.2, 2.0.3"]], printed_rows(context)
    assert_equal "2.0.3", activation.active_version
  end

  def test_a_named_installed_release_is_the_target
    activated("2.0.1", "2.0.2", "2.0.3")

    _, context = preview(target: "2.0.1")

    assert_equal "2.0.1", printed_row(context, "to:")
  end

  def test_with_no_release_installed_it_refuses
    outcome, = preview

    assert_equal [Plastic::Refused, "no release is installed under this home; install one with install.sh first"],
      [outcome.class, outcome.message]
  end

  def test_a_release_that_is_not_installed_is_refused
    activated("2.0.2", "2.0.3")

    assert_equal "1.0.0 is not installed", preview(target: "1.0.0").first.message
  end

  def test_a_single_release_has_nothing_to_go_back_to
    activated("2.0.3")

    assert_equal "no previous release to go back to", preview.first.message
  end

  def test_a_real_run_prints_nothing_and_continues
    activated("2.0.2", "2.0.3")

    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, printed_rows(context)]
  end
end
