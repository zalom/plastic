# frozen_string_literal: true

require "zlib"
require "rubygems/package"
require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/backup/writer"

class KnowledgeBackupWriterTest < Plastic::TestCase
  Writer = Plastic::Graph::Knowledge::Backup::Writer

  def setup
    super
    @backup_home = File.join(@home, "backup-home")
    Plastic::Graph.open(home: @backup_home, store: "plastic").work.write_intent(title: "Alpha")
    File.write(File.join(@backup_home, "config.yml"), "statusline: on\n")
  end

  def entries(name)
    Zlib::GzipReader.open(File.join(@backup_home, "backups", name)) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| return tar.map(&:full_name) }
    end
  end

  def test_the_archive_holds_home_db_each_written_store_database_and_the_home_files
    row = Writer.new(@backup_home, session: "s-1").then { |writer| writer.publish(writer.stage) }

    assert_equal %w[home.db stores/plastic/work_graph.db stores/plastic/knowledge_graph.db origin_id config.yml],
      entries(row.fetch(:name))
  end

  def test_the_row_counts_the_databases_and_hashes_the_archive
    row = Writer.new(@backup_home, session: "s-1").then { |writer| writer.publish(writer.stage) }
    path = File.join(@backup_home, "backups", row.fetch(:name))

    assert_equal [3, Digest::SHA256.file(path).hexdigest, File.size(path), "s-1"], row.values_at(:files, :sha256, :bytes, :session_id)
    assert_match(/\Aplastic-\d{8}-\d{6}\.tar\.gz\z/, row.fetch(:name))
  end

  def test_a_store_database_not_yet_written_has_no_entry
    assert_nil Writer.store_entry(File.join(@backup_home, "stores", "none"), "none", :work)
  end

  def test_each_snapshot_is_a_readable_copy_of_its_database
    source = File.join(@backup_home, "stores", "plastic", "work_graph.db")
    Dir.mktmpdir do |tmp|
      name, dest = Writer.vacuum(tmp, [["work", source]]).first

      assert_equal ["work", 1], [name, Plastic::Graph::Database::ConnectionPool.for(dest).get_first_value("SELECT count(*) FROM intents")]
    end
  end
end
