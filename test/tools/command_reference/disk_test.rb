# frozen_string_literal: true

require_relative "../../command_reference_helper"
require "tmpdir"

class CommandReferenceDiskTest < Minitest::Test
  def with_disk
    Dir.mktmpdir { |root| yield CommandReference::Disk.new(root), root }
  end

  def test_a_file_with_the_same_text_is_not_written_again
    with_disk do |disk, root|
      disk.write("docs/reference/dsl/README.md" => "same")
      path = File.join(root, "docs/reference/dsl/README.md")
      File.utime(Time.at(0), Time.at(0), path)
      disk.write("docs/reference/dsl/README.md" => "same")

      assert_equal Time.at(0), File.mtime(path)
    end
  end

  def test_a_changed_file_is_written_and_a_missing_one_is_removed_with_its_empty_folder
    with_disk do |disk, root|
      disk.write("docs/reference/dsl/README.md" => "one", "docs/reference/commands/a/README.md" => "x")
      disk.write("docs/reference/dsl/README.md" => "two")

      assert_equal({ "docs/reference/dsl/README.md" => "two" }, disk.files)
      refute_path_exists File.join(root, "docs/reference/commands/a")
    end
  end
end
