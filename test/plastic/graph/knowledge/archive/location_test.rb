# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveLocationTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent("Location", status: "future")
    graphs = store_graphs
    @database = graphs.databases.fetch(:work)
    @writer = Plastic::Graph::Knowledge::Archive::Writer.new(graphs.databases, graphs.retrieval, folder, session: "archive-test")
  end

  def test_archive_refuses_an_intent_path_with_parent_traversal
    @database.transaction do |batch|
      batch.write(:intents, "UPDATE intents SET slug = '../../outside' WHERE intent_id = :id", id: @intent.intent_id)
    end

    refute @writer.archive(@intent.intent_id).first
    assert File.directory?(folder.path(@intent.dir))
    refute retrieval.archived?(@intent.intent_id)
  end

  def test_revert_refuses_a_symlink_in_the_destination_parent
    @writer.archive(@intent.intent_id)
    outside = replace_parent_with_symlink

    refute @writer.restore(@intent.intent_id).first
    refute_path_exists File.join(outside, File.basename(@intent.dir))
    assert retrieval.archived?(@intent.intent_id)
  end

  private

  def replace_parent_with_symlink
    parent = folder.path("store")
    outside = File.join(@plastic_home, "moved-store")
    File.rename(parent, outside)
    File.symlink(outside, parent)
    outside
  end
end
