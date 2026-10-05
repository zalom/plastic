# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/sync_up"

class WorkflowSyncUpTest < Plastic::TestCase
  def test_a_spec_written_on_disk_is_read_into_the_rows
    write("#{open_intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")

    outcome, = run_workflow(Plastic::Workflows::SyncUp, overwrite: false, merge: false)

    assert_equal :done, outcome
    assert_equal ["It works"], Plastic::Graph::Knowledge::Spec.new(retrieval, "1").done_criteria
  end
end
