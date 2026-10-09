# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/context_documents"
require_relative "../../../scripts/lib/plastic/workflows/context_persistence"

class ContextDocumentsTest < Plastic::TestCase
  def setup
    super
    open_intent
  end

  def context = call_context(intent_id: "1")

  def read(kind) = Plastic::Workflows::ContextDocuments.new(context).read(kind)

  def test_the_saved_row_is_read
    Plastic::Workflows::ContextPersistence.new(context).persist({ "query" => "row" })

    assert_equal({ "query" => "row" }, read(:context))
  end

  def test_a_file_of_the_store_root_is_never_read
    write("discovery/1.json", JSON.generate("query" => "file"))

    assert_raises(Errno::ENOENT) { read(:discovery) }
  end

  def test_with_neither_the_read_raises
    assert_raises(Errno::ENOENT) { read(:context) }
  end
end
