# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/work/last_savepoints"

class WorkLastSavepointsTest < Plastic::TestCase
  def test_an_intent_with_one_savepoint_gives_its_line
    intent = open_intent

    lines = Plastic::Graph::Work::LastSavepoints.new(retrieval, 5).lines(intent.intent_id)

    assert_equal 1, lines.size
    assert lines.first.end_with?("Opened: Alpha")
  end

  def test_only_the_last_lines_up_to_the_count_come_back
    intent = open_intent
    write("#{intent.dir}/savepoint.md", "step 0\nstep 1\nstep 2\n")
    sync_up

    lines = Plastic::Graph::Work::LastSavepoints.new(retrieval, 2).lines(intent.intent_id)

    assert_equal ["step 1", "step 2"], lines
  end
end
