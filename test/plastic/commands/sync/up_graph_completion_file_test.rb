# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphCompletionFileTest < Minitest::Test
  include DeliveredHomes

  def test_the_graph_file_of_a_delivered_intent_holds_the_completion
    with_homes(method(:deliver)) do |first, _second|
      completion = JSON.parse(first.read(GRAPH)).fetch("completion")

      assert_equal "verdict", completion.fetch("judge")
    end
  end
end
