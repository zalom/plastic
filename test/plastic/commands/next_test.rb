# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/next"
require_relative "../../../scripts/lib/plastic/commands/auto"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_ask"

class NextTest < Plastic::TestCase
  def call(*args) = plastic("next", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def clear_spec(intent) = write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n\n## Open Questions\n- none\n")

  def start(intent)
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)
    plastic("auto", intent.intent_id, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)
  end

  def add_node(intent, title) = plastic("node", "add", intent.intent_id, title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_no_done_criteria_offers_intent_spec
    intent = open_intent

    result = call

    assert_includes result.out, "next: plastic intent spec #{intent.intent_id}"
  end

  def test_an_open_decision_offers_intent_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call

    assert_includes result.out, "next: plastic intent spec #{intent.intent_id}"
  end

  def test_a_spec_without_a_go_ahead_asks_the_owner_and_offers_no_command
    intent = open_intent
    clear_spec(intent)

    result = call

    assert_equal 0, result.code
    assert_includes result.out, "next: none"
    assert_includes result.out, "because: the owner must give the go-ahead for intent #{intent.intent_id}"
    assert_includes result.out, "Ask the owner for the go-ahead. Only after the owner gives it, record it with plastic intent approve #{intent.intent_id}."
    refute_match(/^next: plastic (auto|intent approve)/, result.out)
  end

  def test_an_open_status_with_a_go_ahead_offers_auto_start
    intent = open_intent
    clear_spec(intent)
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)

    result = call

    assert_includes result.out, "next: plastic auto #{intent.intent_id}"
  end

  def test_no_nodes_hands_planning_to_the_harness
    intent = open_intent
    clear_spec(intent)
    start(intent)

    result = call

    assert_includes result.out, "plastic node add #{intent.intent_id} TITLE"
  end

  def test_a_needs_info_node_requests_the_owner_answer
    intent = open_intent
    clear_spec(intent)
    start(intent)
    add_node(intent, "a")
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE)
    plastic("node", "ask", intent.intent_id, "n1", "which way", table: Plastic::CLI::TABLE)

    result = call

    assert_includes result.out, "Ask the owner: which way"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def test_a_failed_node_offers_release
    intent = open_intent
    clear_spec(intent)
    start(intent)
    add_node(intent, "a")
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE)
    plastic("node", "fail", intent.intent_id, "n1", "broke", table: Plastic::CLI::TABLE)

    result = call

    assert_includes result.out, "next: plastic node release #{intent.intent_id} n1"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def test_every_live_node_done_offers_intent_end
    intent = open_intent
    clear_spec(intent)
    start(intent)
    add_node(intent, "a")
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE)
    plastic("node", "done", intent.intent_id, "n1", "ok", table: Plastic::CLI::TABLE)

    result = call

    assert_includes result.out, "next: plastic intent end #{intent.intent_id}"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def test_an_open_node_left_offers_claim
    intent = open_intent
    clear_spec(intent)
    start(intent)
    add_node(intent, "a")

    result = call

    assert_includes result.out, "next: plastic node claim #{intent.intent_id} n1"
  end

  def test_several_candidates_request_a_choice
    first = open_intent("Alpha")
    second = open_intent("Beta")
    clear_spec(first)
    clear_spec(second)
    start(first)
    start(second)

    result = call

    assert_includes result.out, "Inspect plastic status"
  end

  def test_nothing_open_has_no_next_action
    result = call

    assert_includes result.out, "next: none"
  end
end
