# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleasePointerTest < Minitest::Test
  include ReleaseHelper

  def pointer = InstallerRelease::Pointer.new(File.join(@root, "active"))

  def release(version)
    FileUtils.mkdir_p(File.join(@root, "releases", version))
    File.write(File.join(@root, "releases", version, "VERSION"), "#{version}\n")
    File.join("releases", version)
  end

  def test_a_missing_pointer_has_no_target_and_no_version
    assert_equal [nil, nil], [pointer.target, pointer.version]
  end

  def test_pointing_names_the_target_and_reads_its_version
    pointer.point_to(release("2.0.3"))

    assert_equal ["releases/2.0.3", "2.0.3"], [pointer.target, pointer.version]
  end

  def test_pointing_again_replaces_the_target
    pointer.point_to(release("2.0.2"))
    pointer.point_to(release("2.0.3"))

    assert_equal "2.0.3", pointer.version
  end

  def test_pointing_leaves_no_temporary_link_behind
    pointer.point_to(release("2.0.3"))

    assert_equal %w[active releases], Dir.children(@root).sort
  end
end
