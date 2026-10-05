# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/entries"

class KnowledgeArchiveEntriesTest < Plastic::TestCase
  Entries = Plastic::Graph::Knowledge::Archive::Entries
  TreeError = Plastic::Graph::Knowledge::Archive::Tree::Error

  def setup
    super
    @stage = File.join(@plastic_home, "stage")
  end

  def test_an_absolute_path_is_refused
    error = assert_raises(TreeError) { Entries.located(@stage, "/etc/passwd") }

    assert_equal "invalid archive path /etc/passwd", error.message
  end

  def test_a_parent_traversal_is_refused
    error = assert_raises(TreeError) { Entries.located(@stage, "a/../../escaped") }

    assert_equal "invalid archive path a/../../escaped", error.message
  end

  def test_an_unknown_kind_is_refused
    error = assert_raises(TreeError) { Entries.write(@stage, row("pipe", "pipe", nil)) }

    assert_equal "invalid archive entry kind pipe", error.message
  end

  def test_a_link_is_built_pointing_at_its_saved_target
    Entries.build(@stage, [row("", "directory", nil, 0o755), row("note", "link", "INDEX.md", link_mode)])

    assert_equal "INDEX.md", File.readlink(File.join(@stage, "note"))
  end

  def test_a_link_gets_its_saved_mode_when_it_differs
    skip "only macOS can change the mode of a symbolic link" unless RUBY_PLATFORM.include?("darwin")

    Entries.build(@stage, [row("", "directory", nil, 0o755), row("note", "link", "INDEX.md", 0o700)])

    assert_equal 0o700, File.lstat(File.join(@stage, "note")).mode & 0o7777
  end

  private

  def row(path, kind, data, mode = 0o644) = { path:, kind:, data:, mode:, mtime: "0/1" }

  def link_mode
    probe = File.join(@plastic_home, "probe")
    File.symlink("INDEX.md", probe)
    File.lstat(probe).mode & 0o7777
  end
end
