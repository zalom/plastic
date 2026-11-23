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
    assert_match(/`retrieval`.*read-only worker/, ROLE)
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

  def test_a_new_limit_takes_effect_at_a_reinstall
    assert_includes ROLE, "`plastic install --reinstall`"
  end
end
