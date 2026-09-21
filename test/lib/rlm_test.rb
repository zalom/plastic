# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/rlm/query"

class RlmTest < Minitest::Test
  ROWS = {
    "heron" => [{"id" => 1, "path" => "a.md", "excerpt" => "a heron"}, {"id" => 2, "path" => "b.md", "excerpt" => "heron pond"}],
    "pond" => [{"id" => 2, "path" => "b.md", "excerpt" => "heron pond"}, {"id" => 3, "path" => "c.md", "excerpt" => "a pond"}]
  }.freeze

  def setup
    @asked = []
    @corpus = RLM::Corpus.new(lambda { |terms, limit|
      @asked << [terms, limit]
      ROWS.fetch(terms.first, [])
    })
  end

  def test_the_probe_drops_stop_words_and_repeated_terms
    RLM::Probe.new(@corpus, limit: 5).call("Where is the heron and the Heron pond?")

    assert_equal [[["heron"], 5], [["pond"], 5]], @asked
  end

  def test_the_probe_ranks_a_row_that_matches_more_terms_first
    rows = RLM::Probe.new(@corpus).call("heron pond")

    assert_equal [[2, 2], [1, 1], [3, 1]], rows.map { |row| row.values_at("id", "score") }
  end

  def test_the_probe_honors_its_limit
    assert_equal [2], RLM::Probe.new(@corpus, limit: 1).call("heron pond").map { |row| row["id"] }
  end

  def test_a_question_of_stop_words_only_returns_no_row
    assert_empty RLM::Probe.new(@corpus).call("what is the")
  end

  def test_the_query_returns_the_rows_with_no_judge
    assert_equal [2, 1, 3], RLM::Query.new(RLM::Probe.new(@corpus)).call("heron pond").map { |row| row["id"] }
  end

  def test_the_judge_receives_the_question_and_the_rows_above_the_limit
    judge = ->(question, rows) { [question, rows.size] }

    assert_equal ["heron pond", 3], RLM::Query.new(RLM::Probe.new(@corpus), judge: judge, limit: 2).call("heron pond")
  end

  def test_the_judge_is_not_called_at_the_limit
    judge = ->(_question, _rows) { raise "the judge must not run" }

    assert_equal 3, RLM::Query.new(RLM::Probe.new(@corpus), judge: judge, limit: 3).call("heron pond").size
  end

  def test_no_file_of_the_library_names_its_host
    Dir[File.expand_path("../../scripts/lib/rlm/*.rb", __dir__)].each do |file|
      refute_match(/plastic/i, File.read(file), "#{File.basename(file)} must not name its host")
    end
  end

  def test_the_library_has_its_three_files
    assert_equal %w[corpus.rb probe.rb query.rb], Dir.children(File.expand_path("../../scripts/lib/rlm", __dir__)).sort
  end
end
