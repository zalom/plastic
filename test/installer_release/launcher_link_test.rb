# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseLauncherLinkTest < Minitest::Test
  include ReleaseHelper

  def share = File.join(@root, "share")

  def path = File.join(@root, "bin", "plastic")

  def link = InstallerRelease::LauncherLink.new(path, share)

  def setup
    super
    FileUtils.mkdir_p([File.join(share, "active", "bin"), File.dirname(path)])
  end

  def test_a_missing_launcher_is_ours_but_not_linked
    assert_equal [true, false], [link.ours?, link.linked?]
  end

  def test_a_link_into_the_share_is_ours_and_linked
    File.symlink(File.join(share, "active", "bin", "plastic"), path)

    assert_equal [true, true], [link.ours?, link.linked?]
  end

  def test_a_link_to_another_program_is_not_ours
    File.symlink(File.join(@root, "elsewhere", "plastic"), path)

    refute_predicate link, :ours?
  end

  def test_a_launcher_the_user_wrote_is_not_ours
    File.write(path, "#!/bin/sh\n")

    assert_equal [false, false], [link.ours?, link.linked?]
  end
end
