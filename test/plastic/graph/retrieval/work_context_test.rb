# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/retrieval/work_context"

class RetrievalWorkContextTest < Minitest::Test
  Intent = Struct.new(:intent_id, :title, :status)

  # A retrieval graph that answers every search with the hits it is given.
  class Hits
    attr_reader :asked

    def initialize(hits) = (@hits = hits)

    def search_current(terms, limit:) = (@asked = [terms, limit]) && @hits
  end

  def context(hits, intents) = Plastic::Graph::Retrieval::WorkContext.new(Hits.new(hits), intents).rows

  def hit(intent_id, body) = { "intent_id" => intent_id, "path" => "spec.md", "body" => body }

  def test_only_intents_in_progress_get_context
    assert_empty context([hit("2", "text")], [Intent.new("1", "Idea", "open")])
  end

  def test_at_most_three_intents_in_play_get_context
    intents = %w[1 2 3 4].map { |id| Intent.new(id, "Work", "in_progress") }

    assert_equal %w[for\ 1 for\ 2 for\ 3], context([hit("9", "text")], intents).map { |_label, text| text[/\Afor \d/] }
  end

  def test_the_passages_of_the_intent_itself_are_left_out
    rows = context([hit("1", "own"), hit("2", "other")], [Intent.new("1", "Work", "in_progress")])

    assert_equal [["context:", "for 1: 2/spec.md - other"]], rows
  end
end
