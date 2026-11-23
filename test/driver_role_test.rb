# frozen_string_literal: true

require "minitest/autorun"

# Done criterion c2 of intent 487: the shipped driver role tells the session how to run the graph loop.
class DriverRoleTest < Minitest::Test
  ROLE = File.read(File.expand_path("../agents/plastic-driver.md", __dir__)).gsub(/\s+/, " ")

  def test_it_reads_the_ready_nodes
    assert_includes ROLE, "plastic graph ready ID --json"
  end

  def test_it_pairs_each_node_kind_with_its_worker_role
    assert_match(/`orchestrator`.*`plastic-planner`/, ROLE)
    assert_match(/`work`.*`plastic-executor`/, ROLE)
    assert_match(/`retrieval`.*`plastic-retriever`/, ROLE)
  end

  def test_it_hands_the_worker_the_claim_packet
    assert_includes ROLE, "the claim packet is its whole brief"
  end

  def test_the_worker_finishes_with_node_done_and_its_output
    assert_includes ROLE, "`plastic node done ID NODE TEXT --output PATH`"
  end

  def test_a_harness_that_cannot_start_workers_has_the_session_work_the_nodes
    assert_includes ROLE, "work the nodes yourself"
  end

  def test_it_re_plans_the_region_a_failed_node_leaves
    assert_includes ROLE, "`result.repairs`"
    assert_includes ROLE, "re-plan its region"
  end

  def test_the_loop_stops_only_when_nothing_is_ready_and_nothing_needs_repair
    assert_includes ROLE, "Stop when the ready nodes and `result.repairs` are both empty"
  end

  def test_a_node_waiting_for_the_owner_goes_to_the_owner
    assert_includes ROLE, "A `needs_info` or `impeded` node goes to the owner"
    refute_includes ROLE, "or `plastic node resolve`"
  end

  def test_a_new_limit_takes_effect_at_a_reinstall
    assert_includes ROLE, "`plastic install --reinstall`"
  end

  def test_the_driver_picks_the_agent_name_for_each_worker
    assert_includes ROLE, "You pick the `--agent` name for each worker"
    assert_includes ROLE, "with the intent id and the node id"
  end

  def test_the_driver_waits_for_the_notice_and_never_polls
    assert_includes ROLE, "waits for the harness's notice that a worker ended"
    assert_includes ROLE, "does not poll in a loop"
  end
end
