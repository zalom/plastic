# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseHomeSnapshotTest < Minitest::Test
  include ReleaseHelper

  def kept = File.join(@root, "home", "PLASTIC.md")

  def added = File.join(@root, "home", "added.md")

  def snapshot = InstallerRelease::HomeSnapshot.new(File.join(@root, "snapshot"), -> { [kept, added] })

  def setup
    super
    FileUtils.mkdir_p(File.dirname(kept))
    File.write(kept, "before\n")
  end

  def test_take_saves_only_the_paths_that_exist
    assert_equal [[kept, "0"]], snapshot.take
  end

  def test_put_back_restores_a_changed_file
    saved = snapshot.take
    File.write(kept, "after\n")
    snapshot.put_back(saved)

    assert_equal "before\n", File.read(kept)
  end

  def test_put_back_removes_a_path_the_activation_added
    saved = snapshot.take
    File.write(added, "new\n")
    snapshot.put_back(saved)

    refute_path_exists added
  end

  def test_put_back_restores_a_file_the_activation_removed
    saved = snapshot.take
    FileUtils.rm_rf(File.dirname(kept))
    snapshot.put_back(saved)

    assert_equal "before\n", File.read(kept)
  end
end
