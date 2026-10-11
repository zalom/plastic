# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/work/main_session"

class WorkMainSessionTest < Plastic::TestCase
  def lines = Plastic::Graph::Work::MainSession.lines("7")

  def test_each_step_names_its_command_for_the_intent
    assert_equal ["main session: take the delivery lock with plastic auto 7",
      "main session: record each ruling with plastic intent rule 7 TEXT",
      "main session: write spec.md and add the work nodes with plastic node add 7 TITLE --criterion KEY",
      "main session: claim each node as you dispatch it with plastic node claim 7 NODE",
      "main session: judge each node's report and record it with plastic node done 7 NODE TEXT",
      "main session: judge the intent with plastic intent judge 7",
      "main session: close the intent after the merge with plastic intent end 7"], lines
  end

  def test_the_steps_keep_the_id_placeholder_for_the_help_topic
    assert_equal "plastic auto ID", Plastic::Graph::Work::MainSession::STEPS.first.last
  end
end
