# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseReleasesTest < Minitest::Test
  include ReleaseHelper

  def releases = InstallerRelease::Releases.new(@root)

  def test_versions_are_empty_without_a_releases_folder
    assert_empty releases.versions
  end

  def test_versions_sort_by_version_not_by_text
    %w[2.0.10 2.0.9 2.0.3].each { |version| FileUtils.mkdir_p(releases.path(version)) }

    assert_equal %w[2.0.3 2.0.9 2.0.10], releases.versions
  end

  def test_a_version_with_a_folder_is_installed
    FileUtils.mkdir_p(releases.path("2.0.3"))

    assert_equal [true, false], [releases.installed?("2.0.3"), releases.installed?("2.0.4")]
  end

  def test_the_pointer_target_is_relative_to_the_home
    assert_equal "releases/2.0.3", releases.pointer_target("2.0.3")
  end

  def test_a_candidate_on_the_same_disk_is_on_the_same_filesystem
    FileUtils.mkdir_p(releases.root)

    assert releases.same_filesystem?(@root)
  end
end
