# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/rewrite"

class RewriteTest < Plastic::TestCase
  Rewrite = Plastic::Installations::Rewrite

  def test_a_json_rewrite_of_a_linked_file_keeps_the_link_and_writes_the_file_behind_it
    behind, path = linked("settings.json", "{}")
    Rewrite.json(path, "a" => 1)

    assert_equal [true, "{\n  \"a\": 1\n}\n", ["settings.json"]], [File.symlink?(path), File.read(behind), Dir.children(File.dirname(behind))]
  end

  def test_a_text_rewrite_of_a_linked_file_keeps_the_link_and_writes_the_file_behind_it
    behind, path = linked("CLAUDE.md", "old\n")
    Rewrite.text(path, "new")

    assert_equal [true, "new\n", ["CLAUDE.md"]], [File.symlink?(path), File.read(behind), Dir.children(File.dirname(behind))]
  end

  def test_a_dangling_link_is_replaced_by_the_new_file
    path = File.join(@home, "settings.json")
    File.symlink(File.join(@home, "gone.json"), path)
    Rewrite.json(path, "a" => 1)

    assert_equal [false, "{\n  \"a\": 1\n}\n"], [File.symlink?(path), File.read(path)]
  end

  private

  def linked(name, text)
    behind = File.join(@home, "dotfiles", name)
    FileUtils.mkdir_p(File.dirname(behind))
    File.write(behind, text)
    path = File.join(@home, name)
    File.symlink(behind, path)
    [behind, path]
  end
end
