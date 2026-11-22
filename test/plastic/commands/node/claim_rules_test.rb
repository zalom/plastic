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
    cli("sync", "up")
  end

  def packet = JSON.parse(cli("node", "claim", "1", "n1", "--json").out).dig("result", "packet")

  def claim_lines = cli("node", "claim", "1", "n1").out.lines.map(&:chomp)

  def test_the_packet_carries_the_rulings_in_force_and_leaves_superseded_ones_out
    rule("Old")
    rule("New", "--supersedes", "D1")
    rule("Other")

    assert_equal [{ "id" => "D2", "text" => "New" }, { "id" => "D3", "text" => "Other" }], packet.fetch("rulings")
  end

  def test_the_packet_carries_the_constraints_of_the_spec
    write_constraints("No new gem", "Keep it plain")

    assert_equal ["No new gem", "Keep it plain"], packet.fetch("constraints")
  end

  def test_a_packet_with_no_rulings_and_no_constraints_carries_empty_lists
    claimed = packet

    assert_equal [[], [], {}], [claimed.fetch("rulings"), claimed.fetch("constraints"), claimed.fetch("omitted")]
  end

  def test_the_text_claim_prints_each_ruling_in_force_and_each_constraint
    rule("Old")
    rule("New", "--supersedes", "D1")
    write_constraints("No new gem")

    assert_equal ["ruling: D2 New", "constraint: No new gem"], claim_lines.grep(/\A(ruling|constraint):/)
  end

  def test_the_packet_rulings_are_the_ones_the_brief_prints_without_the_superseded
    rule("Old")
    rule("New", "--supersedes", "D1")
    brief = cli("intent", "brief", "1").out.lines.map(&:chomp).grep(/\Aruling:/).reject { |line| line.end_with?("(superseded)") }

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
