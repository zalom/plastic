# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/preview_install"

class PreviewInstallTest < Plastic::TestCase
  include InstallerHelper

  def preview(dry_run: true, env: {})
    run_workflow(Plastic::Workflows::PreviewInstall, harness: scoped_harness(env:), dry_run:)
  end

  def test_a_dry_run_names_the_version_and_the_home
    outcome, context = preview(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") })

    assert_equal [:done, [["preview:", "install 2.0.5 into #{@plastic_home}"]]], [outcome, printed_rows(context)]
  end

  def test_a_dry_run_names_a_file_the_home_already_holds_as_replaced
    installed("2.0.1")
    File.write(File.join(@plastic_home, "PLASTIC.md"), "old\n")

    _, context = preview

    assert_includes printed_rows(context), ["replace:", "PLASTIC.md"]
    assert_equal "old\n", File.read(File.join(@plastic_home, "PLASTIC.md"))
  end

  def test_a_dry_run_names_a_missing_file_as_added
    _, context = preview

    assert_includes printed_rows(context), ["add:", "PLASTIC.md"]
    refute_path_exists File.join(@plastic_home, "PLASTIC.md")
  end

  def test_a_real_run_prints_nothing_and_continues
    outcome, context = preview(dry_run: false)

    assert_equal [:continue, []], [outcome, printed_rows(context)]
  end
end
