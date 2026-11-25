# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleasePlacementTest < Minitest::Test
  include ReleaseHelper

  def destination = File.join(@root, "releases", "2.0.3")

  def placement(candidate = staged_candidate("2.0.3")) = InstallerRelease::Placement.new(candidate, destination)

  def setup
    super
    FileUtils.mkdir_p(File.dirname(destination))
  end

  def test_the_version_is_the_name_of_the_destination
    assert_equal "2.0.3", placement.version
  end

  def test_a_good_candidate_passes_the_check
    assert_nil placement.check
  end

  def test_a_candidate_for_another_version_fails_the_check
    error = assert_raises(InstallerRelease::VerificationError) { placement(staged_candidate("2.0.2")).check }

    assert_equal "candidate version does not match", error.message
  end

  def test_an_existing_release_fails_the_check
    FileUtils.mkdir_p(destination)

    error = assert_raises(InstallerRelease::ActivationError) { placement.check }
    assert_equal "release version already exists", error.message
  end

  def test_undo_after_a_move_puts_the_candidate_back
    moved = placement
    moved.move
    moved.undo

    assert_equal [true, false], [File.directory?(moved.candidate), File.exist?(destination)]
  end

  def test_undo_without_a_move_changes_nothing
    unmoved = placement
    unmoved.undo

    assert_equal [true, false], [File.directory?(unmoved.candidate), File.exist?(destination)]
  end
end
