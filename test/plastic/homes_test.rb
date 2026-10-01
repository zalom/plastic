# frozen_string_literal: true

require_relative "../test_helper"

# Intent 397, D2: the home reset puts back only what a test changed, instead
# of copying the whole fixture back on every test. Every test here drives the
# reset through its two public calls, `begin` and `reset`, the same calls
# `Plastic::TestCase` makes around every kernel test.
class HomesTest < Plastic::TestCase
  fixtures :alpha_synced

  INTENT_DIR = "stores/global/store/1--alpha"

  def store_path(rel) = File.join(@plastic_home, INTENT_DIR, rel)

  def test_a_rewritten_file_of_the_same_size_and_time_is_put_back
    path = store_path("spec.md")
    original = File.read(path)
    stat = File.stat(path)
    rewritten = "x" * original.bytesize

    refute_equal original, rewritten
    File.write(path, rewritten)
    File.utime(stat.atime, stat.mtime, path)

    @template.reset

    assert_equal original, File.read(path)
  end

  def test_a_deleted_fixture_file_comes_back
    path = store_path("savepoint.md")
    original = File.read(path)
    File.delete(path)

    @template.reset

    assert_path_exists path
    assert_equal original, File.read(path)
  end

  def test_new_files_and_folders_are_removed
    folder = File.join(@home, "junk")
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "file.txt"), "junk")

    @template.reset

    refute_path_exists folder
  end

  def test_a_new_database_is_closed_and_removed
    path = File.join(@plastic_home, "extra.db")
    pool = Plastic::Graph::Database::ConnectionPool
    pool.for(path).execute("CREATE TABLE junk (id INTEGER)")

    @template.reset

    refute_path_exists path
    refute_includes pool.connections.keys, path
  end

  def test_a_replaced_entry_is_put_back
    path = store_path("graph.json")
    original = File.read(path)
    File.delete(path)
    FileUtils.mkdir_p(path)

    @template.reset

    assert_equal "file", File.ftype(path)
    assert_equal original, File.read(path)
  end

  def link_to_outside_target
    outside = Dir.mktmpdir("homes-test-outside")
    target_file = File.join(outside, "kept.txt")
    File.write(target_file, "kept")
    File.symlink(outside, File.join(@home, "link_out"))
    [outside, target_file]
  end

  def test_a_link_outside_the_home_is_removed_and_its_target_kept
    outside, target_file = link_to_outside_target
    link = File.join(@home, "link_out")

    @template.reset

    refute_path_exists link
    assert_equal "kept", File.read(target_file)
  ensure
    FileUtils.rm_rf(outside)
  end

  def test_a_changed_mode_is_put_back
    path = store_path("1--alpha.md")
    original_mode = File.stat(path).mode & 0o777
    changed_mode = (original_mode == 0o600) ? 0o644 : 0o600
    File.chmod(changed_mode, path)

    @template.reset

    assert_equal original_mode, File.stat(path).mode & 0o777
  end

  def test_rollback_journals_are_left_to_the_rollback
    journal = File.join(@plastic_home, "home.db-journal")
    File.write(journal, "not a real journal, just a marker")

    @template.reset

    assert_path_exists journal
    assert_equal "not a real journal, just a marker", File.read(journal)
  ensure
    FileUtils.rm_f(journal)
  end

  def test_a_written_row_is_rolled_back
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global")
    graphs.work.write_intent(title: "Junk")

    @template.reset

    after = Plastic::Graph.open(home: @plastic_home, store: "global")

    refute(after.retrieval.intents.any? { |intent| intent.title == "Junk" })
  end

  def test_an_untouched_home_keeps_every_inode
    path = File.join(@plastic_home, "stores/global/store/index.json")
    before = File.stat(path).ino

    @template.reset

    assert_equal before, File.stat(path).ino
  end
end
