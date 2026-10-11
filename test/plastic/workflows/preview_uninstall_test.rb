# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/preview_uninstall"

class PreviewUninstallTest < Plastic::TestCase
  include InstallerHelper

  def preview(picked, dry_run: true)
    run_workflow(Plastic::Workflows::PreviewUninstall, harness: scoped_harness(env: { "PLASTIC_SHARE" => share }), dry_run:, picked:)
  end

  def install_for(*folders)
    folders.each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("init", "a")
  end

  def removed(context) = printed_rows(context).filter_map { |label, path| path if label == "remove:" }

  def test_a_dry_run_names_what_the_record_lists_and_keeps_the_home
    install_for(".claude")

    outcome, context = preview(["claude-code"])

    assert_equal [:done, ["keep:", @plastic_home]], [outcome, printed_rows(context).last]
    assert_includes removed(context), File.join(@home, ".claude", "plastic")
    assert_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
  end

  def test_a_dry_run_names_the_settings_file_it_would_change
    install_for(".claude")

    _, context = preview(["claude-code"])

    assert_includes printed_rows(context), ["change:", File.join(@home, ".claude", "settings.json")]
  end

  def test_removing_the_last_harness_names_the_releases
    install_for(".claude")
    activated("2.0.3")

    _, context = preview(["claude-code"])

    assert_includes removed(context), share
  end

  def test_a_harness_that_stays_recorded_keeps_the_releases
    install_for(".claude", ".codex")
    activated("2.0.3")

    _, context = preview(["claude-code"])

    refute_includes removed(context), share
  end

  def test_a_real_run_prints_nothing_and_continues
    outcome, context = preview([], dry_run: false)

    assert_equal [:continue, []], [outcome, printed_rows(context)]
  end
end
