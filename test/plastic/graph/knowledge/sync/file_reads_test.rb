# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncFileReadsTest < Plastic::TestCase
  fixtures :alpha

  DIR = "store/1--alpha"

  def sync_read(*names)
    names.each { |name| write("#{DIR}/#{name}", "# #{name}\n") }
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).read(names.map { |name| "#{DIR}/#{name}" })
  end

  def fts(sql) = store_graphs.databases.fetch(:knowledge).rows(sql).map { |row| row.fetch("body") }

  def test_a_first_sync_of_documents_makes_them_searchable
    sync_read("notes.md", "other.md")

    assert_equal ["# other.md\n"], fts("SELECT body FROM document_fts WHERE document_fts MATCH 'other'")
    assert_equal ["# notes.md\n"], fts("SELECT body FROM document_fts WHERE path = 'notes.md'")
  end

  def test_a_second_sync_of_a_changed_document_replaces_its_search_rows
    sync_read("notes.md")
    write("#{DIR}/notes.md", "# changed words\n")
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).read(["#{DIR}/notes.md"])

    assert_equal ["# changed words\n"], fts("SELECT body FROM document_fts WHERE path = 'notes.md'")
  end
end
