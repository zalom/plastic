# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/share"

class ShareTest < Plastic::TestCase
  def root = File.join(@home, "share")

  def share = Plastic::Installations::Share.new(root)

  def release(version)
    directory = FileUtils.mkdir_p(File.join(root, "releases", version)).first
    File.write(File.join(directory, "VERSION"), "#{version}\n")
  end

  def point(name, version) = File.symlink(File.join("releases", version), File.join(root, name))

  def test_an_empty_share_has_no_active_version_and_no_releases
    assert_equal [nil, nil, []], [share.active_version, share.previous_version, share.versions]
  end

  def test_reads_the_active_and_previous_versions_from_the_pointed_releases
    %w[2.0.3 2.0.4].each { |version| release(version) }
    point("active", "2.0.4")
    point("previous", "2.0.3")

    assert_equal ["2.0.4", "2.0.3"], [share.active_version, share.previous_version]
  end

  def test_lists_the_releases_oldest_first_by_version_order
    %w[2.0.10 2.0.9 2.0.9-beta.1].each { |version| release(version) }

    assert_equal %w[2.0.9-beta.1 2.0.9 2.0.10], share.versions
  end

  def test_a_share_with_releases_holds_a_release
    refute_predicate share, :release?
    release("2.0.3")

    assert_predicate share, :release?
  end

  def test_a_share_with_only_a_version_file_holds_a_release
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "VERSION"), "1.9.0\n")

    assert_predicate share, :release?
  end

  def test_the_active_path_is_the_active_pointer
    assert_equal File.join(root, "active"), share.active_path
  end

  def test_the_launcher_link_is_judged_against_this_share
    path = File.join(@home, "bin", "plastic")
    FileUtils.mkdir_p(File.dirname(path))
    File.symlink(File.join(root, "active", "bin", "plastic"), path)

    assert_predicate share.launcher_link(path), :linked?
  end
end
