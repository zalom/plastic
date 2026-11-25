# frozen_string_literal: true

require_relative "release_helper"
require_relative "../../scripts/lib/installer_release/share_entries"

class InstallerReleaseShareEntriesTest < Minitest::Test
  include ReleaseHelper

  def setup
    super
    FileUtils.mkdir_p([File.join(share, "rubies", "4.0.7-jdx-2", "bin"), File.join(share, "releases", "2.0.3")])
    File.write(File.join(share, "INSTALL.lock"), "")
    File.symlink("releases/2.0.3", File.join(share, "active"))
  end

  def test_the_ruby_folder_goes_last
    assert_equal "rubies", entries.order.last
  end

  def test_removes_a_read_only_ruby_and_the_emptied_share
    FileUtils.chmod_R("a-w", File.join(share, "rubies"))

    assert entries.remove
    refute_path_exists share
  end

  def test_a_share_with_a_file_plastic_did_not_make_stays_with_that_file
    File.write(File.join(share, "notes.txt"), "mine")

    refute entries.remove
    assert_equal ["notes.txt"], Dir.children(share)
  end

  private

  def share = File.join(@root, "share")

  def entries = InstallerRelease::ShareEntries.new(share)
end
