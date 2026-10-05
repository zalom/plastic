# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/release_removal"

class ReleaseRemovalTest < Plastic::TestCase
  def teardown
    InstallerRelease::Rubies.remove(share)
    super
  end

  def test_removes_a_read_only_ruby_with_the_releases_and_the_share
    installed
    rows = removal.call

    assert_equal [["removed:", launcher], ["removed:", share]], rows
    refute_path_exists share
  end

  def test_keeps_the_files_plastic_did_not_make
    installed
    File.write(File.join(share, "notes.txt"), "mine\n")
    rows = removal.call

    assert_equal ["notes.txt"], Dir.children(share)
    assert_includes rows, ["kept:", "#{share} holds files Plastic did not make; they stay"]
  end

  def test_removes_a_stopped_download
    installed
    FileUtils.mkdir_p(File.join(share, "plastic-stage-1234"))
    removal.call

    refute_path_exists share
  end

  def test_removes_a_share_from_before_the_releases_layout
    FileUtils.mkdir_p(File.join(share, "lib"))
    File.write(File.join(share, "VERSION"), "1.9.0\n")
    File.write(File.join(share, "lib", "plastic.rb"), "\n")
    rows = removal.call

    assert_equal [["removed:", share]], rows
    refute_path_exists share
  end

  def test_removes_only_the_launcher_when_the_share_holds_no_release
    installed
    FileUtils.rm_rf(File.join(share, "releases"))

    assert_equal [["removed:", launcher]], removal.call
    assert_path_exists File.join(share, "rubies")
  end

  def test_keeps_a_launcher_plastic_does_not_own
    installed
    File.unlink(launcher)
    File.write(launcher, "#!/bin/sh\n")

    assert_equal [["removed:", share], ["kept:", "#{launcher} is not Plastic's launcher; it stays"]], removal.call
  end

  def test_plans_nothing_for_a_share_without_releases
    FileUtils.mkdir_p(share)

    assert_empty removal.planned
  end

  private

  def share = File.join(@home, ".local", "share", "plastic")

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def removal = Plastic::Workflows::ReleaseRemoval.new(share: share, launcher: launcher)

  def installed
    release = FileUtils.mkdir_p(File.join(share, "releases", "2.0.3", "bin")).first
    File.write(File.join(release, "plastic"), "#!/bin/sh\n")
    File.symlink(File.join("releases", "2.0.3"), File.join(share, "active"))
    read_only_ruby
    linked_launcher
  end

  def linked_launcher
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink(File.join(share, "active", "bin", "plastic"), launcher)
  end

  def read_only_ruby
    ruby = FileUtils.mkdir_p(File.join(share, "rubies", "4.0.7-jdx-2", "bin")).first
    File.write(File.join(ruby, "ruby"), "#!/bin/sh\n")
    FileUtils.chmod_R("a-w", File.dirname(ruby))
  end
end
