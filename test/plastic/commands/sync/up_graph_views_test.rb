# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphViewsTest < Minitest::Test
  include TwoHomes

  def test_graph_show_and_graph_resume_say_the_same_in_both_homes
    with_two_homes do |first, second|
      second.run!("sync", "up")

      assert_equal first.run!("graph", "show", "1").out, second.run!("graph", "show", "1").out
      assert_equal first.run!("graph", "resume").out, second.run!("graph", "resume").out
    end
  end
end
