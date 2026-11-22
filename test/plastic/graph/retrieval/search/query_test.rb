# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/search/query"

class RetrievalSearchQueryTest < Minitest::Test
  def query(text) = Plastic::Graph::Retrieval::Search::Query.new(text).to_s

  def test_the_words_of_a_question_are_quoted_and_joined_with_or
    assert_equal '"graph" OR "context"', query("graph context")
  end

  def test_a_word_is_never_read_as_fts_syntax
    assert_equal '"NEAR" OR "x"', query("NEAR( x* )")
  end

  def test_common_words_drop_out_when_other_words_remain
    assert_equal '"retrieval"', query("what is the retrieval")
  end

  def test_common_words_stay_when_they_are_all_there_is
    assert_equal '"what" OR "is"', query("what is")
  end

  def test_a_repeated_word_is_asked_once
    assert_equal '"graph"', query("graph Graph graph")
  end

  def test_a_quoted_phrase_is_one_term_and_keeps_the_common_words_out_of_the_rest
    assert_equal '"retrieval graph"', query('"retrieval graph" is the')
  end

  def test_an_empty_phrase_adds_nothing
    assert_equal '"graph"', query('"" graph')
  end
end
