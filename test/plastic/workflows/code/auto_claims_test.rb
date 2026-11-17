# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/workflows/code/auto"

# plastic auto goes active and takes no lock: the claims of the nodes are the ownership.
class WorkflowAutoTakesNoLockTest < Plastic::TestCase
  include DeliveryHelper

  def start = run_workflow(Plastic::Workflows::Code::Auto, harness: scoped_harness(session: "s-1"), graphs: session_graphs, intent_id: "1").first

  def tables = store_graphs.databases.fetch(:local).rows("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }

  def test_the_intent_goes_active_and_no_lock_row_or_table_exists
    specified_intent
    plastic("intent", "approve", "1", table: Plastic::CLI::TABLE)

    assert_equal [:done, "in_progress"], [start, retrieval.intent("1").status]
    refute_includes tables, "locks"
  end

  def test_another_session_holding_a_node_does_not_stop_the_start
    specified_intent
    plastic("intent", "approve", "1", table: Plastic::CLI::TABLE)
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-2")

    assert_equal :done, start
  end
end
