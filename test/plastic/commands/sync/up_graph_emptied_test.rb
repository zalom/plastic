# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphEmptiedTest < Minitest::Test
  include TwoHomes

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
