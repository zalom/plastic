# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/prune"

class PruneTest < Plastic::TestCase
  Prune = Plastic::Installations::Prune

  def prune(*roots) = Prune.new(home: @plastic_home, roots: roots.empty? ? [@plastic_home] : roots)

  def test_a_prune_inside_the_intent_store_is_refused_with_a_plain_warning
    path = File.join(@plastic_home, "store", "x.md")
    _, err = capture_io { assert_equal 0, prune.call([path]) }

    assert_equal "   Refused to prune #{path}: inside the intent store\n", err
  end

  def test_a_prune_outside_the_root_is_skipped_with_a_plain_warning
    outside = File.join(@home, "elsewhere.md")
    File.write(outside, "x")
    _, err = capture_io { assert_equal 0, prune.call([outside]) }

    assert_equal ["   Skipped prune of #{outside}: outside #{@plastic_home}\n", true], [err, File.exist?(outside)]
  end

  def test_a_stale_file_is_deleted_and_its_emptied_folder_removed
    file = File.join(@plastic_home, "old", "deep", "a.md")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")

    assert_equal [1, false], [prune.call([file, File.join(@plastic_home, "old", "gone.md")]), File.exist?(File.join(@plastic_home, "old"))]
  end

  def test_a_folder_that_still_holds_a_file_stays
    file = File.join(@plastic_home, "old", "a.md")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    File.write(File.join(@plastic_home, "old", "mine.md"), "y")
    prune.call([file])

    assert_path_exists File.join(@plastic_home, "old", "mine.md")
  end
end
