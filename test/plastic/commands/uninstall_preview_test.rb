# frozen_string_literal: true

require_relative "installer_helper"

class UninstallPreviewCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
  end

  def test_a_dry_run_lists_the_files_it_would_remove_and_changes_nothing
    before = tree_snapshot(@home)
    result = call("uninstall", "--dry-run", "1")

    assert_match(%r{remove:\s+.*\.claude/}, result.out)
    assert_match(/keep:\s+.*\.plastic/, result.out)
    assert_equal before, tree_snapshot(@home)
  end

  def test_the_preview_lists_every_path_the_uninstall_removes
    activated("2.0.0")
    paths = home_paths
    listed = call("uninstall", "--dry-run", "a").out.scan(/^(?:remove|change):\s+(\S+)/).flatten

    call("uninstall", "a")
    gone = paths.reject { |entry| File.exist?(entry) || File.symlink?(entry) }

    assert_empty gone.reject { |entry| listed.any? { |item| entry == item || entry.start_with?("#{item}/") } }
  end

  def home_paths = Dir.glob(File.join(@home, "**", "*"), File::FNM_DOTMATCH).reject { |entry| entry.end_with?("/.", "/..") }
end
