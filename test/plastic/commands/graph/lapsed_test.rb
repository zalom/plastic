# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/lapsed"
require_relative "../../../../lib/plastic/commands/graph/ready"
require_relative "../../../../lib/plastic/commands/intent/auto"
require_relative "../../../../lib/plastic/commands/intent/start"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/claim"

# `graph lapsed` lists every intent in agent delivery whose driver claim or node claim lapsed, and names the command
# that restarts the work. It reads the rows and changes nothing.
class GraphLapsedTest < Plastic::TestCase
  START = Time.utc(2026, 11, 24, 9, 0, 0)
  STAMP = "2026-11-24T09:00:00Z"
  Clock = Struct.new(:now)

  def run_at(minutes, *argv, session: "s-orchestrator")
    plastic(*argv, env: { "PLASTIC_SESSION" => session }, table: Plastic::CLI::TABLE, clock: Clock.new(START + (minutes * 60)))
  end

  def lapsed(minutes, *flags, session: "s-orchestrator") = run_at(minutes, "graph", "lapsed", *flags, session:)

  def lapsed_json(minutes) = JSON.parse(lapsed(minutes, "--json").out).dig("result", "lapsed")

  # An intent in progress, started with `words` by the orchestrating session, with one node that a helper claimed.
  def delivery(words = "auto", helper: "s-orchestrator")
    open_keyed_intent
    run_at(0, "intent", words, "1")
    run_at(0, "node", "add", "1", "Build", "--criterion", "done")
    run_at(0, "node", "claim", "1", "n1", "--agent", "tester", session: helper)
  end

  def driver_row = store_database.row("SELECT seen_at FROM drivers WHERE intent_id = '1'")

  def test_a_lapsed_driver_claim_of_an_agent_delivery_is_listed_and_restarted_with_intent_auto
    delivery

    result = lapsed(16)

    assert_call result, code: 0, err: "",
      out: ["lapsed: store global, intent 1 Alpha, driver, session s-orchestrator, last renewed #{Plastic.local(STAMP)}",
        "next: plastic intent auto 1", "because: the driver claim of intent 1 lapsed; plastic intent auto 1 takes it"]
  end

  def test_a_lapsed_node_claim_is_listed_with_the_agent_that_held_it_and_restarted_with_node_claim
    delivery(helper: "s-helper")
    run_at(10, "graph", "ready", "1")

    result = lapsed(20)

    assert_call result, code: 0, err: "",
      out: ["lapsed: store global, intent 1 Alpha, node n1 Build, agent tester, session s-helper, last renewed #{Plastic.local(STAMP)}",
        "next: plastic node claim 1 n1 --agent tester", "because: the claim of node n1 of intent 1 lapsed; plastic node claim takes it for a new helper"]
  end

  def test_a_live_driver_claim_and_a_live_node_claim_are_not_listed
    delivery

    result = lapsed(10)

    assert_call result, code: 0, err: "", out: "because: no agent delivery has a lapsed claim\n"
  end

  def test_an_intent_in_guided_work_is_not_listed_when_its_claims_lapse
    delivery("start")

    result = lapsed(60)

    assert_call result, code: 0, err: "", out: "because: no agent delivery has a lapsed claim\n"
  end

  def test_the_json_answer_carries_each_lapsed_claim
    delivery(helper: "s-helper")

    assert_equal [{ "store" => "global", "intent_id" => "1", "title" => "Alpha", "claim" => "driver", "node" => nil, "node_title" => nil,
                    "agent" => nil, "session" => "s-orchestrator", "last_renewed" => STAMP },
      { "store" => "global", "intent_id" => "1", "title" => "Alpha", "claim" => "node", "node" => "n1", "node_title" => "Build",
        "agent" => "tester", "session" => "s-helper", "last_renewed" => STAMP }], lapsed_json(16)
  end

  def test_the_json_answer_carries_an_empty_list_when_nothing_lapsed
    delivery

    assert_empty lapsed_json(5)
  end

  def test_the_holder_running_the_command_renews_no_claim
    delivery
    lapsed(16)

    assert_equal [STAMP, STAMP], [driver_row["seen_at"], store_graphs.retrieval.node("1", "n1").seen_at]
  end

  def test_several_named_stores_are_read_in_the_order_named
    register_blog
    delivery

    assert_includes lapsed(16, "--stores", "blog,global").out, "next: plastic intent auto 1\n"
  end

  def test_a_lapsed_claim_in_another_store_names_that_store_in_the_restart
    register_blog
    blog = Plastic::Graph.open(home: @plastic_home, store: "blog").work
    blog.write_intent(title: "Beta")
    blog.activate_intent("1")
    Plastic::Graph.open(home: @plastic_home, store: "blog", session: "s-orchestrator", clock: Clock.new(START)).work.drive_intent(intent_id: "1", by: "s-orchestrator", mode: "auto")

    assert_includes lapsed(16, "--stores", "global,blog").out, "next: plastic intent auto 1 --project blog\n"
  end

  def register_blog
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  blog:\n    path: #{Dir.mktmpdir}\n")
    Plastic::Graph.create(home: @plastic_home, store: "blog")
  end

  def test_stores_and_a_project_together_are_a_usage_error
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  blog:\n    path: #{Dir.mktmpdir}\n")

    result = lapsed(0, "--stores", "global", "--project", "blog")

    assert_call result, code: 2, out: "", err: /--stores names the stores; --project does not apply/
  end
end
