# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/sync/down"

class WorkflowSyncDownTest < Plastic::TestCase
  def test_a_new_node_row_is_printed_into_graph_json
    intent = open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build")

    outcome, = run_workflow(Plastic::Workflows::Code::Sync::Down, overwrite: false, merge: false)

    assert_equal :done, outcome
    assert_includes File.read(store_path("#{intent.dir}/graph.json")), "Build"
  end
end
