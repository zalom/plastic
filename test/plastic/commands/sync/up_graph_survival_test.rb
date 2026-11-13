# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphSurvivalTest < Minitest::Test
  include TwoHomes

  def test_findings_that_hold_id_and_intent_id_survive_the_move_unchanged
    with_two_homes do |_first, second|
      second.run!("sync", "up")

      assert_equal ["The test is red for the right reason; see :id and :intent_id"], query(second, "SELECT findings FROM nodes WHERE id = 'n1'").flatten
    end
  end

  def test_a_graph_emptied_in_one_home_is_read_in_the_other_and_empties_the_rows_there
    with_two_homes do |first, second|
      second.run!("sync", "up")
      emptied = JSON.pretty_generate(JSON.parse(second.read(GRAPH)).merge("approval" => nil, "verdicts" => [], "nodes" => [], "edges" => []))
      second.write(GRAPH, "#{emptied}\n")
      second.run!("sync", "up")
      first.write(GRAPH, second.read(GRAPH))
      first.run!("sync", "up")

      assert_equal [[], []], [query(second, "SELECT id FROM nodes"), query(first, "SELECT id FROM nodes")]
    end
  end
end
