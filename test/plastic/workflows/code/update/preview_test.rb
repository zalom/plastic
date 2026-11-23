# frozen_string_literal: true

require_relative "../../../commands/installer_helper"
require_relative "../../../../../lib/plastic/workflows/code/update/preview"

class PreviewUpdateTest < Plastic::TestCase
  include InstallerHelper

  def preview(dry_run: true, newest: "2.0.5", **options)
    facts = { channel: nil }.merge(options)
    env = { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5"), "PLASTIC_LOCAL_RELEASE" => local_release(newest) }
    run_workflow(Plastic::Workflows::Code::Update::Preview, harness: scoped_harness(env: env.merge("PLASTIC_SHARE" => share)), dry_run:, **facts)
  end

  def test_a_dry_run_names_both_versions
    installed("2.0.1")

    outcome, context = preview

    assert_equal [:done, [["from:", "2.0.1"], ["to:", "2.0.5"]]], [outcome, printed_rows(context)]
  end

  def test_a_dry_run_names_the_newest_release_on_the_channel_when_the_running_package_is_not_newer
    installed("2.0.5")
    activated("2.0.5")

    outcome, context = preview(newest: "2.0.7")

    assert_equal [:done, [["from:", "2.0.5"], ["to:", "2.0.7"]]], [outcome, printed_rows(context)]
  end

  def test_a_dry_run_names_the_installed_version_when_nothing_newer_exists
    installed("2.0.5")
    activated("2.0.5")

    outcome, context = preview(newest: "2.0.5")

    assert_equal [:done, [["from:", "2.0.5"], ["to:", "2.0.5"]]], [outcome, printed_rows(context)]
  end

  def test_a_home_with_nothing_installed_is_refused
    error = assert_raises(Plastic::Refused) { preview }

    assert_equal [Plastic::Refused, "Plastic is not installed under this home; run plastic install first"],
      [error.class, error.message]
  end

  def test_a_home_with_only_a_release_from_install_sh_continues_from_that_release
    activated("2.0.3")

    outcome, context = preview(newest: "2.0.4")

    assert_equal [:done, [["from:", "2.0.3"], ["to:", "2.0.4"]]], [outcome, printed_rows(context)]
  end

  def test_a_real_run_prints_nothing_and_continues
    installed("2.0.1")

    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, printed_rows(context)]
  end
end
