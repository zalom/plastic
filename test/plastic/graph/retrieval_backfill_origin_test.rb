# frozen_string_literal: true

require_relative "../../test_helper"

class RetrievalBackfillOriginTest < Plastic::TestCase
  def test_one_origin_completion_does_not_complete_another_origin
    first = retrieval.origin_id
    second = "second-origin"
    write_document(first, "first.md", "first text")
    write_document(second, "second.md", "second text")

    complete(first)

    assert_first_does_not_complete_second(first, second)
    complete(second)

    assert_second_completion
  end

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)
  def complete(origin) = Plastic::Graph::ReferenceBackfill.new(store_graphs.databases, origin).call

  def assert_first_does_not_complete_second(first, second)
    assert Plastic::Graph::ReferenceBackfill.complete?(knowledge.path, first)
    refute Plastic::Graph::ReferenceBackfill.complete?(knowledge.path, second)
  end

  def assert_second_completion
    assert Plastic::Graph::ReferenceBackfill.complete?(knowledge.path, "second-origin")
    assert_equal ["first.md", "second.md"], knowledge.rows("SELECT path FROM document_heads ORDER BY path").map { |row| row.fetch("path") }
  end

  def write_document(origin, path, body)
    knowledge.transaction do |batch|
      batch.add("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', :path, :body, 'then', :origin)", path:, body:, origin:)
    end
  end
end
