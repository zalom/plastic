# frozen_string_literal: true

require "zlib"
require "stringio"
require "rubygems/package"
require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/backup/tar_entry_writer"

class KnowledgeBackupTarEntryWriterTest < Plastic::TestCase
  def tar_of(name, bytes)
    io = StringIO.new
    tar = Gem::Package::TarWriter.new(io)
    Plastic::Graph::Knowledge::Backup::TarEntryWriter.new(tar, io).add(name, bytes)
    tar.close
    io.rewind
    Gem::Package::TarReader.new(io).map { |entry| [entry.full_name, entry.read] }
  end

  def test_a_short_name_writes_a_plain_entry
    assert_equal [["stores/plastic/home.db", "bytes"]], tar_of("stores/plastic/home.db", "bytes")
  end

  def test_a_name_too_long_for_a_ustar_header_writes_a_gnu_long_name_entry_before_the_file
    name = "stores/#{"s" * 300}/work_graph.db"

    assert_equal [["././@LongLink", "#{name}\0"], [name[0, 100], "bytes"]], tar_of(name, "bytes")
  end
end
