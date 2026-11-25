# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/launcher_link"

class LauncherLinkTest < Plastic::TestCase
  def share = File.join(@home, "share")

  def path = File.join(@home, "bin", "plastic")

  def link = Plastic::Installations::LauncherLink.new(path, share)

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
    File.symlink(File.join(@home, "elsewhere", "plastic"), path)

    refute_predicate link, :ours?
  end

  def test_a_link_to_a_retired_launcher_is_ours_but_not_linked
    retired = File.join(@home, ".plastic", "bin", "plastic")
    File.symlink(retired, path)

    link = Plastic::Installations::LauncherLink.new(path, share, retired: [retired])

    assert_equal [true, false], [link.ours?, link.linked?]
  end

  def test_a_launcher_the_user_wrote_is_not_ours
    File.write(path, "#!/bin/sh\n")

    assert_equal [false, false], [link.ours?, link.linked?]
  end
end
