# frozen_string_literal: true

require "digest"
require "sqlite3"
require "tmpdir"
require_relative "../../lib/plastic/graph/schema/sequences"

# A knowledge file at the layout of store migration 5 and a references.db beside it with two kept files, a changes row and a printed row.
module ReferencesPair
  Layout = Plastic::Graph::SchemaStore1::Layout::TEXT
  Migration = Plastic::Graph::SchemaStore6
  FILES = { "notes/a.md" => "alpha bytes", "notes/b.bin" => "\x00\x01binary\xFF".b }.freeze

  def setup
    super
    @folder = Dir.mktmpdir
    @knowledge = SQLite3::Database.new(knowledge_path, results_as_hash: true)
    @knowledge.execute_batch(Layout.fetch(:knowledge) + Plastic::Graph::SchemaStore4::TEXT.fetch(:knowledge))
    @knowledge.execute("PRAGMA user_version = 5")
    seed_references
  end

  def knowledge_path = File.join(@folder, "knowledge_graph.db")

  def references_path = File.join(@folder, "references.db")

  def references = SQLite3::Database.new(references_path, results_as_hash: true)

  def seed_references
    database = references
    database.execute_batch(Layout.fetch(:references))
    FILES.each { |name, data| insert_kept(database, name, data) }
    database.execute("INSERT INTO changes (\"table\", \"key\", operation, \"row\", at, origin_id) VALUES ('sqlar', 'notes/a.md', 'put', '{}', 't', 'o')")
    database.execute("INSERT INTO printed (path, sha256, at, origin_id) VALUES ('notes/a.md', 'h', 't', 'o')")
  ensure
    database&.close
  end

  def insert_kept(database, name, data)
    database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (?, 420, 1, ?, ?, '1', ?, 'o')", [name, data.bytesize, SQLite3::Blob.new(data), Digest::SHA256.hexdigest(data)])
  end

  def apply(**) = Migration.apply(@knowledge, :knowledge, { knowledge: knowledge_path }, **)

  def kept = @knowledge.execute("SELECT name, data, sha256 FROM sqlar ORDER BY name").to_h { |row| [row["name"], [row["data"].b, row["sha256"]]] }
end
