# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/files"

class FilesTest < Plastic::TestCase
  Files = Plastic::Installations::Files

  def test_json_with_comments_and_trailing_commas_is_read
    path = File.join(@home, "loose.json")
    File.write(path, %({ "a": 1, // note\n }))

    assert_equal({ "a" => 1 }, Files.read_json(path))
  end

  def test_garbage_and_a_missing_file_read_as_nil
    path = File.join(@home, "garbage.json")
    File.write(path, "{ broken")

    assert_equal [nil, nil], [Files.read_json(path), Files.read_json(File.join(@home, "absent.json"))]
  end

  def test_json_is_written_pretty_with_a_closing_newline_and_no_temporary_left
    path = File.join(@home, "out.json")
    Files.write_json(path, "a" => 1)

    assert_equal ["{\n  \"a\": 1\n}\n", ["out.json"]], [File.read(path), Dir.children(@home).grep(/out/)]
  end

  def test_a_linked_file_keeps_its_link_and_the_file_behind_it_is_written
    behind = File.join(@home, "dotfiles", "settings.json")
    FileUtils.mkdir_p(File.dirname(behind))
    File.write(behind, "{}")
    path = File.join(@home, "settings.json")
    File.symlink(behind, path)
    Files.write_json(path, "a" => 1)
    Files.write_text(path, "text\n")

    assert_equal [true, "text\n", ["settings.json"]], [File.symlink?(path), File.read(behind), Dir.children(File.dirname(behind))]
  end

  def test_a_write_into_a_missing_folder_raises_and_leaves_no_temporary
    assert_raises(Errno::ENOENT) { Files.write_text(File.join(@home, "missing", "out.md"), "x") }
  end

  def test_a_file_that_exists_is_not_overwritten
    path = File.join(@home, "note.md")
    Files.write_if_missing(path, "first\n")
    Files.write_if_missing(path, "second\n")

    assert_equal "first\n", File.read(path)
  end

  def test_a_sibling_that_shares_a_prefix_is_not_contained
    root = File.join(@home, "x")

    assert_equal [true, true, false], [File.join(root, "a"), root, "#{root}-evil"].map { |path| Files.contained?(path, [root]) }
  end

  def test_a_symlink_resolves_to_its_target_and_a_plain_path_stays
    target = File.join(@home, "target.md")
    link = File.join(@home, "link.md")
    File.write(target, "x")
    File.symlink(target, link)

    assert_equal [File.realpath(target), target, File.join(@home, "none")],
      [Files.resolve(link), Files.resolve(target), Files.resolve(File.join(@home, "none"))]
  end

  def test_a_dangling_symlink_resolves_to_itself
    link = File.join(@home, "dangling.md")
    File.symlink(File.join(@home, "gone"), link)

    assert_equal link, Files.resolve(link)
  end
end
