# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/preview_update"

class PreviewUpdateTest < Plastic::TestCase
  include InstallerHelper

  def preview(dry_run: true, **channels)
    facts = { stable: false, beta: false, alpha: false }.merge(channels)
    env = { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") }
    run_workflow(Plastic::Workflows::PreviewUpdate, harness: scoped_harness(env:), dry_run:, **facts)
  end

  def test_a_dry_run_names_both_versions
    installed("2.0.1")

    outcome, context = preview

    assert_equal [:done, [["from:", "2.0.1"], ["to:", "2.0.5"]]], [outcome, printed_rows(context)]
  end

  def test_a_home_with_nothing_installed_is_refused
    outcome, = preview

    assert_equal [Plastic::Refused, "Plastic is not installed under this home; run plastic install first"],
      [outcome.class, outcome.message]
  end

  def test_two_channels_are_refused
    installed("2.0.1")

    assert_equal "choose one channel: --stable, --beta or --alpha", preview(beta: true, alpha: true).first.message
  end

  def test_a_real_run_prints_nothing_and_continues
    installed("2.0.1")

    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, printed_rows(context)]
  end
end
