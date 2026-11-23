# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/check"
require_relative "../../../../lib/plastic/commands/node/add"

# A node whose stored output is not JSON is a finding with no repair command: the output was edited by hand.
class GraphCheckOutputTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1", "--agent", "tester")
    cli("node", "done", "1", "n1", "built")
  end

  def hold_output(text)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:nodes, "UPDATE nodes SET output = '#{text}' WHERE intent_id = '1' AND id = 'n1'")
    end
  end

  def check = cli("graph", "check", "1")

  def test_output_that_is_not_json_is_a_finding_that_names_the_node
    hold_output("not json")

    assert_includes check.out, "finding: node n1 holds output that is not JSON\n"
  end

  def test_output_that_is_json_is_no_finding
    hold_output('{"a":1}')

    assert_includes check.out, "no findings"
  end

  def test_a_node_with_no_output_is_no_finding
    assert_includes check.out, "no findings"
  end

  def test_a_finding_with_no_repair_command_prints_no_repair_and_no_next_line
    hold_output("not json")
    result = check

    refute_match(/^(repair|next):/, result.out)
    assert_equal 1, result.code
  end

  def test_the_finding_names_its_own_hand_edit_with_a_sync_up
    hold_output("not json")

    assert_includes check.out, "hand edit: edit the output of node n1 in graph.json to hold JSON, then run plastic sync up and plastic graph check 1 again\n"
  end
end
