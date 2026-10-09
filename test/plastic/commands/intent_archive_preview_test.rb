# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class IntentArchivePreviewTest < Plastic::TestCase
  def seed_folder(home)
    seed_intents(home, "Target")
    mark_done_in(home, "1")
    folder = File.join(home, "stores", "global", "store", "1--target")
    File.write(File.join(folder, "notes.txt"), "notes")
    File.write(File.join(File.dirname(home), "outside.txt"), "outside")
    File.symlink(File.join(File.dirname(home), "outside.txt"), File.join(folder, "ref.txt"))
  end

  def test_an_archive_preview_lists_the_removed_files
    twin = twin_run("intent", "archive", "1") { |home| seed_folder(home) }
    folder = File.join(twin.first, "stores", "global", "store", "1--target")

    assert_equal [], twin.changed_paths
    assert_includes twin.preview_paths, "remove #{folder}/notes.txt"
    assert_includes twin.preview_paths, "remove #{folder}/intent.md"
  end

  def test_an_archive_preview_leaves_the_link_target_untouched
    twin = twin_run("intent", "archive", "1") { |home| seed_folder(home) }

    assert_equal "outside", File.read(File.join(File.dirname(twin.first), "outside.txt"))
  end

  def test_an_unarchive_preview_matches_apply_on_an_identical_home
    twin = twin_run("intent", "unarchive", "1") do |home|
      seed_intents(home, "Target")
      mark_done_in(home, "1")
      call_in(home, "intent", "archive", "1")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end

  def test_an_unarchive_preview_of_an_intent_already_restored_fails_like_the_apply
    twin = twin_run("intent", "unarchive", "1") do |home|
      seed_intents(home, "Target")
      mark_done_in(home, "1")
      call_in(home, "intent", "archive", "1")
      call_in(home, "intent", "unarchive", "1")
    end

    assert_preview_matches_apply(twin)
  end
end
