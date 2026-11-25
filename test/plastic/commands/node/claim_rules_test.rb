# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"

class NodeClaimRulesTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
  end

  def rule(text, *options) = cli("intent", "rule", "1", text, *options)

  def write_constraints(*items)
    write("#{retrieval.intent("1").dir}/spec.md", "#{keyed_spec({ KEY => CRITERION })}\n## Constraints\n#{items.map { |item| "- #{item}\n" }.join}")
    cli("store", "sync", "up")
  end

  def packet = JSON.parse(cli("node", "claim", "1", "n1", "--agent", "tester", "--json").out).dig("result", "packet")

  def claim_lines = cli("node", "claim", "1", "n1", "--agent", "tester").out.lines.map(&:chomp)

  def test_the_packet_carries_every_ruling_each_addition_after_its_decision
    rule("Old")
    rule("Other")
    rule("New", "--adds", "D1")

    assert_equal [{ "id" => "D1", "text" => "Old" }, { "id" => "D1.1", "text" => "New" }, { "id" => "D2", "text" => "Other" }], packet.fetch("rulings")
  end

  def test_the_packet_carries_the_constraints_of_the_spec
    write_constraints("No new gem", "Keep it plain")

    assert_equal ["No new gem", "Keep it plain"], packet.fetch("constraints")
  end

  def test_a_packet_with_no_rulings_and_no_constraints_carries_empty_lists
    claimed = packet

    assert_equal [[], [], {}], [claimed.fetch("rulings"), claimed.fetch("constraints"), claimed.fetch("omitted")]
  end

  def test_the_text_claim_prints_each_ruling_as_rewritten_and_each_constraint
    rule("Old")
    rule("New", "--rewrites", "D1")
    write_constraints("No new gem")

    assert_equal ["ruling: D1 New", "constraint: No new gem"], claim_lines.grep(/\A(ruling|constraint):/)
  end

  def test_the_packet_rulings_are_the_ones_the_brief_prints
    rule("Old")
    rule("New", "--adds", "D1")
    brief = cli("intent", "brief", "1").out.lines.map(&:chomp).grep(/\Aruling:/)

    assert_equal brief, claim_lines.grep(/\Aruling:/)
  end

  def test_the_packet_keeps_the_newest_twenty_rulings_and_counts_the_rest
    22.times { |number| rule("Ruling #{number}") }
    claimed = packet

    assert_equal [20, "D22", { "rulings" => 2 }], [claimed.fetch("rulings").size, claimed.fetch("rulings").last.fetch("id"), claimed.fetch("omitted")]
  end

  def test_the_text_claim_says_how_many_rulings_it_left_out
    22.times { |number| rule("Ruling #{number}") }

    assert_includes claim_lines, "omitted: 2 rulings; plastic intent brief 1 lists them all"
  end
end
