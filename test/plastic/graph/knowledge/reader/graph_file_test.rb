# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderGraphFileTest < Plastic::TestCase
  GraphFile = Plastic::Graph::Knowledge::Reader::GraphFile
  PATH = "store/1--alpha/graph.json"

  def problems(data) = GraphFile.new(data.is_a?(String) ? data : JSON.generate({ "intent" => "1" }.merge(data)), "1", nil, PATH).problems

  def test_a_file_that_is_no_json_names_the_parse_error
    assert_equal 1, problems("{not json").size
    assert_includes problems("{not json").first, "#{PATH} is not valid JSON: "
  end

  def test_a_file_whose_json_is_not_an_object_is_refused
    assert_equal ["#{PATH} is not valid JSON: it is not an object"], problems("[1, 2]")
  end

  def test_a_file_that_holds_nothing_but_its_intent_has_no_problem
    assert_empty problems({})
  end

  def test_a_node_that_is_not_an_object_is_refused
    assert_equal ["#{PATH} holds a node that is not an object"], problems("nodes" => ["n1"])
  end

  def test_an_edge_that_is_a_bare_name_must_name_a_node
    assert_equal ["#{PATH} holds an edge to \"n5\", which is no node it holds"], problems("edges" => ["n5"])
  end

  def test_an_edge_between_the_nodes_of_the_file_is_accepted
    nodes = [{ "id" => "n1", "state" => "done" }, { "id" => "n2", "state" => "done" }]

    assert_empty problems("nodes" => nodes, "edges" => [{ "from" => "n1", "to" => "n2" }])
  end

  def test_a_file_that_names_no_intent_says_so_in_words
    text = JSON.generate({})

    assert_equal ["#{PATH} names no intent, not 1"], GraphFile.new(text, "1", nil, PATH).problems
  end

  def test_a_file_that_names_another_intent_quotes_it
    text = JSON.generate({ "intent" => "2" })

    assert_equal ["#{PATH} names intent \"2\", not 1"], GraphFile.new(text, "1", nil, PATH).problems
  end

  def test_a_node_with_no_state_says_so_in_words
    assert_equal ["#{PATH} holds node \"n1\" with no state"], problems("nodes" => [{ "id" => "n1" }])
  end

  def test_a_node_in_an_unknown_state_names_the_state
    assert_equal ["#{PATH} holds node \"n1\" in the unknown state \"stuck\""], problems("nodes" => [{ "id" => "n1", "state" => "stuck" }])
  end

  def test_an_edge_with_no_end_says_so_in_words
    nodes = [{ "id" => "n1", "state" => "done" }]

    assert_equal ["#{PATH} holds an edge with no end"], problems("nodes" => nodes, "edges" => [{ "from" => "n1" }])
  end

  def test_a_verdict_that_is_not_an_object_is_refused
    assert_equal ["#{PATH} holds the verdict \"accept\""], problems("verdicts" => ["accept"])
  end

  def test_a_verdict_outside_the_known_verdicts_is_refused
    assert_equal 1, problems("verdicts" => [{ "verdict" => "maybe" }]).size
  end

  def test_an_approval_with_an_unknown_field_is_refused
    assert_equal ["#{PATH} holds the unknown field mood in approvals"], problems("approval" => { "mood" => "good" })
  end

  def test_an_entry_that_is_not_an_object_has_no_unknown_field
    assert_empty problems("verdicts" => []).grep(/unknown field/)
  end
end
