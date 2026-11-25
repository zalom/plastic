# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderFolderFileTest < Plastic::TestCase
  def file = Plastic::Graph::Knowledge::Reader::FolderFile.new(folder, "store/1--alpha/spec.md", "spec.md")

  def test_a_folder_file_reads_its_bytes_from_the_store
    write("store/1--alpha/spec.md", "# Spec\n")

    assert_equal "# Spec\n", file.bytes
  end

  def test_a_folder_file_reads_its_modification_time_in_seconds
    write("store/1--alpha/spec.md", "# Spec\n")
    File.utime(Time.iso8601(STAMP), Time.iso8601(STAMP), folder.path("store/1--alpha/spec.md"))

    assert_equal Time.iso8601(STAMP).to_i, file.mtime
  end

  def test_a_missing_folder_file_raises_on_its_time
    assert_raises(Errno::ENOENT) { file.mtime }
  end
end
