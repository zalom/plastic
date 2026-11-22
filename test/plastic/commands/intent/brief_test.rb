# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/brief"
require_relative "../../../../lib/plastic/commands/intent/rule"
require_relative "../../../../lib/plastic/commands/node/add"

class IntentBriefCaseTest < Plastic::TestCase
  def test_the_brief_of_an_intent_started_from_a_legacy_roadmap_carries_the_goal_and_the_done_criteria_of_its_batch
    legacy_roadmap
    ran("roadmap next make-it-useful --batch 1", "roadmap open make-it-useful 2")

    assert_case line("intent brief 2"), code: 0, out: ["goal: Close the two blockers",
      "criterion: a guest sees only their own order", "criterion: add to cart works on every page"]
  end

  def test_the_brief_after_a_full_pass_of_the_work_graph_shows_the_rulings_and_the_ready_node
    work_graph_pass

    assert_case line("intent brief 1"), code: 0, out: ["ruling: D1 Flowbite styles every delivery (superseded)",
      "ruling: D2 Direct mode only", "ready: n2 build it"]
  end

  MAIN_SESSION = ["main session: record each ruling with plastic intent rule 1 TEXT",
    "main session: write spec.md and add the work nodes with plastic node add 1 TITLE --criterion KEY",
    "main session: claim each node as you dispatch it with plastic node claim 1 NODE",
    "main session: judge each node's report and record it with plastic node done 1 NODE TEXT",
    "main session: judge the intent with plastic intent judge 1",
    "main session: close the intent after the merge with plastic intent end 1"].freeze
  PLAN_STEP = "1. Before you plan, fetch the architecture map as current as possible with an architecture mapping tool such as Enola, " \
    "or map the code yourself; Plastic runs no tool. Read the intent's goal and done criteria. Add work with plastic node add 1 TITLE " \
    "--criterion KEY, then add dependencies with plastic edge add. An edge FROM TO means TO reads, changes or tests what FROM makes. " \
    "Nodes with no path between them may run at the same time. A red test node comes before the code it tests. " \
    "Run plastic graph check 1 after the edges and repair each finding it names, then use plastic graph ready 1."

  def test_a_brief_with_no_spec_says_where_the_agent_writes_it
    ran("intent new Alpha", "intent start 1")

    assert_case line("intent brief 1"), code: 0, out: ["goal: Alpha",
      'spec: none yet; the agent writes store/1--alpha/spec.md, and the done criteria are the bullets under its "## Done criteria" heading, ' \
      "each written - [c1] text", *MAIN_SESSION, PLAN_STEP, "plastic node fail ID NODE TEXT is for work that was tried and failed."]
  end

  def test_a_brief_with_a_spec_a_ruling_and_a_node_names_each_and_offers_the_claim
    alpha_specified("# Spec\n\n## Done criteria\n\n- [tests-pass] the CLI ships\n")
    ran("intent approve 1", "intent start 1", 'intent rule 1 "ship the CLI first"', "node add 1 Build --criterion tests-pass")

    assert_case line("intent brief 1"), code: 0, out: ["goal: Alpha",
      'spec: store/1--alpha/spec.md; the done criteria are the bullets under its "## Done criteria" heading, each written - [c1] text',
      "criterion: [tests-pass] the CLI ships", "ruling: D1 ship the CLI first", "ready: n1 Build", *MAIN_SESSION,
      "next: plastic node claim 1 n1"]
  end

  def test_a_brief_of_a_missing_intent_exits_1_and_names_it
    assert_case line("intent brief 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentBriefTest < Plastic::TestCase
  def call(*args) = plastic("intent", "brief", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def briefed_intent
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    plastic("intent", "rule", intent.intent_id, "Flowbite styles every delivery", table: Plastic::CLI::TABLE)
    plastic("intent", "rule", intent.intent_id, "Direct mode only", "--supersedes", "D1", table: Plastic::CLI::TABLE)
    plastic("node", "add", intent.intent_id, "do the thing", "--criterion", "ships", table: Plastic::CLI::TABLE)
    intent
  end

  def test_names_the_goal_and_the_done_criteria
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert_includes result.out, "goal: Alpha"
    assert_includes result.out, "criterion: ships"
  end

  def test_the_spec_line_shows_one_example_criterion
    intent = briefed_intent

    assert_includes call(intent.intent_id).out, "- [c1] "
  end

  def test_names_each_goal_line_the_spec_holds
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Goal\n\nClose the two blockers\nLock down guest orders\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    assert_includes result.out, "goal: Close the two blockers\ngoal: Lock down guest orders\n"
    refute_includes result.out, "goal: Alpha"
  end

  def test_marks_the_superseded_ruling_and_keeps_the_other_plain
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_includes result.out, "ruling: D1 Flowbite styles every delivery (superseded)"
    assert_includes result.out, "ruling: D2 Direct mode only"
    refute_includes result.out, "ruling: D2 Direct mode only (superseded)"
  end

  def test_names_the_ready_node_and_the_command_usage
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_includes result.out, "ready: n1 do the thing"
    assert_includes result.out, "plastic node add ID"
    assert_includes result.out, "plastic edge add ID"
  end

  def test_a_parked_intent_offers_no_command_and_names_its_reason
    open_intent(status: "parked", reason: "waits on review")

    result = call("1")

    refute_match(/^next: /, result.out)
    assert_call result, code: 0, err: "",
      out: ["because: intent 1 is parked: waits on review; plastic intent start 1 resumes the work once the reason is resolved\n"]
  end

  def test_misses_nothing_on_an_empty_intent
    intent = open_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute_includes result.out, "ruling:"
    refute_includes result.out, "ready:"
  end

  def test_the_command_gives_the_workflow_the_usage_of_the_node_and_edge_commands
    usages = Plastic::Commands::Intent::Brief.given_facts.fetch(:command_usages)

    assert_equal 11, usages.size
    assert_includes usages, Plastic::Commands::Edge::Remove.usage_line
  end
end
