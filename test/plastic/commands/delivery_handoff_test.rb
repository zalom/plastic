# frozen_string_literal: true

require_relative "../../test_helper"

class DeliveryHandoffTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "delivery" })

  def active_intent
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- Ships\n")
    cli("sync", "up")
    cli("auto", "1")
    intent
  end

  def test_an_empty_graph_hands_planning_to_the_harness
    active_intent

    result = cli("intent", "brief", "1")

    assert_includes result.out, "plastic node add"
    assert_includes result.out, "next: none"
  end

  def test_a_done_graph_leads_to_explicit_intent_verification
    active_intent
    cli("node", "add", "1", "Ship", "--criterion", "Ships")
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "--judge", "tool", "--findings", "Checked")

    result = cli("graph", "ready", "1")

    assert_includes result.out, "next: plastic intent end 1"
  end
end
