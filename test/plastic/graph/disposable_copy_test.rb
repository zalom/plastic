# frozen_string_literal: true

require_relative "../../test_helper"

class DisposableCopyTest < Plastic::TestCase
  def copy_of(home) = Plastic::Graph::DisposableCopy.new(home, "global")

  def seed(home)
    seed_intents(home, "Alpha")
    File.write(File.join(home, "stores", "global", "store", "1--alpha", "notes.txt"), "kept\n")
  end

  def test_the_copy_holds_the_rows_and_the_files_of_the_home
    with_home do |home|
      seed(home)

      copy_of(home).within do |copy|
        opened = Plastic::Graph.open(home: copy.path, store: "global")

        assert_equal "Alpha", opened.retrieval.intent("1").title
        assert_equal "kept\n", File.read(File.join(copy.path, "stores", "global", "store", "1--alpha", "notes.txt"))
        assert_equal File.read(File.join(home, "origin_id")), File.read(File.join(copy.path, "origin_id"))
      end
    end
  end

  def test_the_copy_is_removed_after_the_block_and_after_an_error
    with_home do |home|
      seed(home)
      kept = nil
      copy_of(home).within { |copy| kept = copy.path }

      refute_path_exists kept
      assert_raises(RuntimeError) { copy_of(home).within { |copy| (kept = copy.path) && raise("boom") } }
      refute_path_exists kept
    end
  end

  def test_a_home_with_no_store_copies_without_error
    with_home do |home|
      FileUtils.mkdir_p(home)

      copy_of(home).within { |copy| assert_path_exists copy.path }
    end
  end

  def test_a_symbolic_link_is_copied_as_a_link_and_its_target_is_untouched
    with_home do |home|
      seed(home)
      outside = File.join(File.dirname(home), "outside.txt")
      File.write(outside, "outside\n")
      File.symlink(outside, File.join(home, "stores", "global", "store", "1--alpha", "link.txt"))

      copy_of(home).within do |copy|
        link = File.join(copy.path, "stores", "global", "store", "1--alpha", "link.txt")

        assert File.symlink?(link)
        assert_equal "outside\n", File.read(link)
      end
      assert_equal "outside\n", File.read(outside)
    end
  end

  def test_a_write_through_a_file_link_never_reaches_the_outside_target
    with_home do |home|
      seed(home)
      outside = File.join(File.dirname(home), "outside.txt")
      File.write(outside, "outside\n")
      File.symlink(outside, File.join(home, "stores", "global", "store", "1--alpha", "link.txt"))

      copy_of(home).within do |copy|
        File.write(File.join(copy.path, "stores", "global", "store", "1--alpha", "link.txt"), "changed\n")
      end

      assert_equal "outside\n", File.read(outside)
    end
  end

  def test_a_link_to_a_folder_refuses_and_the_folder_is_untouched
    with_home do |home|
      seed(home)
      outside = File.join(File.dirname(home), "outside")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "a.txt"), "a\n")
      link = File.join(home, "stores", "global", "store", "1--alpha", "folder")
      File.symlink(outside, link)
      before = snapshot(outside)

      error = assert_raises(Plastic::Graph::DisposableCopy::Refused) { copy_of(home).within { flunk "the copy must refuse" } }

      assert_includes error.message, link
      assert_equal before, snapshot(outside)
    end
  end

  def test_the_changes_name_the_added_changed_and_removed_files_by_original_path
    with_home do |home|
      seed(home)
      store = File.join(home, "stores", "global")

      changes = copy_of(home).within do |copy|
        inside = File.join(copy.path, "stores", "global")
        File.write(File.join(inside, "store", "1--alpha", "notes.txt"), "changed\n")
        File.delete(File.join(inside, "store", "1--alpha", "savepoint.md"))
        File.write(File.join(inside, "added.txt"), "new\n")
        copy.changes
      end

      assert_equal [["would add", File.join(store, "added.txt")],
        ["would change", File.join(store, "store", "1--alpha", "notes.txt")],
        ["would remove", File.join(store, "store", "1--alpha", "savepoint.md")]], changes
    end
  end

  def test_the_copy_rewrites_its_own_path_to_the_original_path
    with_home do |home|
      seed(home)

      copy_of(home).within do |copy|
        assert_equal "printed #{home}/stores/global/x", copy.original("printed #{copy.path}/stores/global/x")
      end
    end
  end
end
