# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/next"
require_relative "../../../lib/plastic/commands/intent/auto"
require_relative "../../../lib/plastic/commands/node/add"
require_relative "../../../lib/plastic/commands/node/claim"
require_relative "../../../lib/plastic/commands/node/done"
require_relative "../../../lib/plastic/commands/node/fail"
require_relative "../../../lib/plastic/commands/node/ask"

class NextPlanStepCaseTest < Plastic::TestCase
  PLAN_STEP = "1. Before you plan, fetch the architecture map as current as possible with an architecture mapping tool such as Enola, " \
    "or map the code yourself; Plastic runs no tool. Read the intent's goal and done criteria. Add work with plastic node add 1 TITLE " \
    "--criterion KEY, then add dependencies with plastic edge add. " \
    "An edge FROM TO means TO reads, changes or tests what FROM makes. Nodes with no path between them may run at the same time. " \
    "A red test node comes before the code it tests. Run plastic graph check 1 after the edges and repair each finding it names, " \
    "then use plastic graph ready 1. " \
    "Every plan and every planned code change follows the Principle of Least Surprise: a name does what it says, a word means the same " \
    "thing everywhere, nothing has hidden side effects, and standard conventions come first. The work graph handles every ambiguity, " \
    "newly found issue and blocker. Resolve an ambiguity by search or research with at least 3 attempts, then ask with plastic node ask " \
    "ID NODE TEXT, naming the question and what you tried. An impediment such as no access, a missing source or missing resources stops " \
    "the node at once: plastic node impede ID NODE TEXT. plastic node resolve ID NODE TEXT reopens either. A newly found issue becomes " \
    "a new node with plastic node add --found-in NODE, naming the node it was found in, and plastic edge add. plastic node fail ID NODE TEXT is for work that was tried and failed."

  def test_a_locked_intent_with_no_plan_hands_the_agent_the_plan_step
    alpha_specified(UNKEYED_CRITERION)
    ran("intent approve 1", "intent auto 1")

    assert_case line("next"), code: 0, out: [PLAN_STEP]
  end
end

class NextTest < Plastic::TestCase
  def call(*args) = plastic("next", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def clear_spec(intent) = write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n\n## Open Questions\n- none\n")

  def start(intent)
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)
    plastic("intent", "start", intent.intent_id, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)
  end

  def add_node(intent, title) = plastic("node", "add", intent.intent_id, title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_no_done_criteria_offers_intent_spec
    intent = open_intent

    result = call

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic intent spec #{intent.intent_id}"
  end

  def test_an_open_decision_offers_intent_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call

    assert_includes result.out, "next: plastic intent spec #{intent.intent_id}"
  end

  def test_an_open_status_with_a_go_ahead_offers_intent_start
    intent = open_intent
    clear_spec(intent)
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)

    result = call

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic intent start #{intent.intent_id}"
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
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "ask", intent.intent_id, "n1", "which way", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

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
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "fail", intent.intent_id, "n1", "broke", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

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
    plastic("node", "claim", intent.intent_id, "n1", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "done", intent.intent_id, "n1", "ok", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

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

    assert_equal [0, ""], [result.code, result.err]
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

  def test_nothing_open_sends_the_agent_to_status
    result = call

    assert_match(/^next: plastic status$/, result.out)
  end
end

class NextWithoutGoAheadTest < Plastic::TestCase
  def test_a_spec_without_a_go_ahead_asks_the_owner_and_offers_no_command
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- [done] ships\n\n## Open Questions\n- none\n")
    plastic("sync", "up", table: Plastic::CLI::TABLE)
    result = plastic("next", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: "1. Ask the owner for the go-ahead. Only after the owner gives it, record it with plastic intent approve 1.\nbecause: the owner must give the go-ahead for intent 1\n"
  end
end

class NoNextNoneTest < Plastic::TestCase
  def next_lines(result) = result.out.lines(chomp: true).grep(/\Anext: /)

  def leave_as_the_installer_does = Plastic::Graph.create(home: @plastic_home, store: "global")

  def test_nothing_open_sends_the_agent_to_status_and_says_why
    result = plastic("next", table: Plastic::CLI::TABLE)

    assert_equal [0, ["next: plastic status"], ""], [result.code, next_lines(result), result.err]
    assert_includes result.out, "because: nothing is open"
  end

  def test_a_hand_off_with_no_command_prints_no_next_line_and_says_why
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- [done] ships\n")
    plastic("sync", "up", table: Plastic::CLI::TABLE)
    result = plastic("next", table: Plastic::CLI::TABLE)

    assert_equal [0, []], [result.code, next_lines(result)]
    assert_includes result.out, "because: the owner must give the go-ahead for intent 1"
  end

  def test_json_names_status_as_next_when_nothing_is_open
    result = plastic("next", "--json", table: Plastic::CLI::TABLE)
    answer = JSON.parse(result.out)

    assert_equal "plastic status", answer.fetch("next")
    assert_equal "nothing is open", answer.fetch("because")
  end

  def test_json_error_with_no_offer_names_a_null_next
    result = plastic("intent", "show", "99", "--json", table: Plastic::CLI::TABLE)
    answer = JSON.parse(result.out)

    assert_nil answer.fetch("next")
    refute_equal "none", answer.fetch("next")
  end

  def test_a_search_with_no_hit_on_a_fresh_home_prints_no_next_line_and_exits_0
    leave_as_the_installer_does
    result = plastic("search", "nothing-matches-this", table: Plastic::CLI::TABLE)

    assert_equal [0, [], ""], [result.code, next_lines(result), result.err]
  end

  def test_a_document_lookup_that_finds_nothing_prints_no_next_line
    leave_as_the_installer_does
    result = plastic("document", "get", "plastic://global/1/spec.md", table: Plastic::CLI::TABLE)

    assert_equal [1, []], [result.code, next_lines(result)]
    refute_includes result.err, "maintenance is required"
  end

  def test_no_command_text_output_has_no_closing_next_line
    output = Plastic::CLI::Result.new.tap { |answer| answer.offer(nil, "a reason") }

    assert_equal ["because: a reason"], output.closing_lines(nil)
  end
end

class DeliveryHandoffTest < Plastic::TestCase
  include LifecycleHelper

  def active_intent
    intent = specified(records: nil)
    cli("intent", "approve", "1")
    cli("intent", "auto", "1")
    intent
  end

  def test_an_empty_graph_hands_planning_to_the_harness
    active_intent

    result = cli("intent", "brief", "1")

    assert_includes result.out, "plastic node add"
    refute_match(/^next: /, result.out)
  end

  def test_a_done_graph_leads_to_explicit_intent_verification
    active_intent
    cli("node", "add", "1", "Ship", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "Checked")

    result = cli("next")

    assert_includes result.out, "next: plastic intent end 1"
  end

  def test_the_handoff_texts_name_no_judge_option
    active_intent
    cli("node", "add", "1", "Ship", "--criterion", KEY)
    brief = cli("intent", "brief", "1").out
    claimed = cli("node", "claim", "1", "n1").out

    [brief, claimed].each { |text| refute_includes text, "--judge" }
    assert_includes claimed, "plastic node done 1 n1 TEXT"
  end
end
