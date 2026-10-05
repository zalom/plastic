# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseFlatShareTest < Minitest::Test
  include ReleaseHelper

  def share = File.join(@root, "share")

  def releases = InstallerRelease::Releases.new(share)

  def migrate = InstallerRelease::FlatShare.new(share, releases).migrate

  def flat_install
    FileUtils.mkdir_p([File.join(share, "bin"), File.join(share, "rubies")])
    File.write(File.join(share, "VERSION"), "2.0.2\n")
    File.write(File.join(share, "bin", "plastic"), "#!/bin/sh\n")
    File.write(File.join(share, "plastic-download-1"), "")
  end

  def test_a_flat_install_moves_into_its_release_folder
    flat_install
    migrate

    assert_equal %w[VERSION bin], Dir.children(releases.path("2.0.2")).sort
  end

  def test_a_flat_install_becomes_the_active_release
    flat_install
    migrate

    assert_equal "2.0.2", InstallerRelease::Pointer.new(File.join(share, "active")).version
  end

  def test_the_kept_folders_and_downloads_stay_in_the_share
    flat_install
    migrate

    assert_equal %w[active plastic-download-1 releases rubies], Dir.children(share).sort
  end

  def test_a_share_with_an_active_pointer_is_not_moved
    flat_install
    File.symlink("releases/2.0.2", File.join(share, "active"))
    migrate

    assert_path_exists File.join(share, "bin", "plastic")
  end

  def test_a_share_without_a_version_is_not_moved
    FileUtils.mkdir_p(share)

    assert_nil migrate
  end
end
