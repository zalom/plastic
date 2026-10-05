# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/disposable_copy"

# The seeded home and the links the tests of the copy build.
module DisposableCopyFixtures
  def alpha(home, *rest) = File.join(home, "stores", "global", "store", "1--alpha", *rest)

  def with_seed
    with_home do |home|
      seed_intents(home, "Alpha")
      File.write(alpha(home, "notes.txt"), "kept\n")
      yield home
    end
  end

  def linked_file(home)
    File.join(File.dirname(home), "outside.txt").tap do |outside|
      File.write(outside, "outside\n")
      File.symlink(outside, alpha(home, "link.txt"))
    end
  end

  def folder_link(home)
    outside = File.join(File.dirname(home), "outside")
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, "a.txt"), "a\n")
    File.symlink(outside, alpha(home, "folder"))
    [alpha(home, "folder"), outside]
  end

  def rework(copy_path)
    File.write(alpha(copy_path, "notes.txt"), "changed\n")
    File.delete(alpha(copy_path, "savepoint.md"))
    File.write(File.join(copy_path, "stores", "global", "added.txt"), "new\n")
  end
end

class DisposableCopyTest < Plastic::TestCase
  include DisposableCopyFixtures

  def copy_of(home) = Plastic::Graph::DisposableCopy.new(home, "global")

  def test_the_copy_holds_the_rows_of_the_home
    with_seed do |home|
      copy_of(home).within do |copy|
        assert_equal "Alpha", Plastic::Graph.open(home: copy.path, store: "global").retrieval.intent("1").title
      end
    end
  end

  def test_the_copy_holds_the_files_of_the_home
    with_seed do |home|
      copy_of(home).within do |copy|
        assert_equal "kept\n", File.read(alpha(copy.path, "notes.txt"))
        assert_equal File.read(File.join(home, "origin_id")), File.read(File.join(copy.path, "origin_id"))
      end
    end
  end

  def test_the_copy_is_removed_after_the_block
    with_seed do |home|
      kept = copy_of(home).within(&:path)

      refute_path_exists kept
    end
  end

  def test_the_copy_is_removed_after_an_error
    with_seed do |home|
      kept = nil
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

  def test_a_symbolic_link_is_copied_as_a_link_that_reads_the_target
    with_seed do |home|
      linked_file(home)

      copy_of(home).within do |copy|
        assert File.symlink?(alpha(copy.path, "link.txt"))
        assert_equal "outside\n", File.read(alpha(copy.path, "link.txt"))
      end
    end
  end

  def test_a_write_through_a_file_link_never_reaches_the_outside_target
    with_seed do |home|
      outside = linked_file(home)
      copy_of(home).within { |copy| File.write(alpha(copy.path, "link.txt"), "changed\n") }

      assert_equal "outside\n", File.read(outside)
    end
  end

  def test_a_link_to_a_folder_refuses_naming_the_link
    with_seed do |home|
      link, = folder_link(home)
      error = assert_raises(Plastic::Graph::DisposableCopy::Refused) { copy_of(home).within { flunk "the copy must refuse" } }

      assert_includes error.message, link
    end
  end

  def test_a_link_to_a_folder_leaves_the_folder_untouched
    with_seed do |home|
      _link, outside = folder_link(home)
      before = snapshot(outside)
      assert_raises(Plastic::Graph::DisposableCopy::Refused) { copy_of(home).within { flunk "the copy must refuse" } }

      assert_equal before, snapshot(outside)
    end
  end

  def test_the_changes_name_the_added_changed_and_removed_files_by_original_path
    with_seed do |home|
      store = File.join(home, "stores", "global")
      changes = copy_of(home).within { |copy| rework(copy.path).then { copy.changes } }

      assert_equal [["would add", File.join(store, "added.txt")], ["would change", alpha(home, "notes.txt")],
        ["would remove", alpha(home, "savepoint.md")]], changes
    end
  end

  def test_the_copy_rewrites_its_own_path_to_the_original_path
    with_seed do |home|
      copy_of(home).within do |copy|
        assert_equal "printed #{home}/stores/global/x", copy.original("printed #{copy.path}/stores/global/x")
      end
    end
  end
end
