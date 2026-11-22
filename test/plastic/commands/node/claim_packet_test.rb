# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"

class NodeClaimPacketTest < Plastic::TestCase
  include LifecycleHelper

  OUTPUT = "{\n  \"files\": [\"a.rb\"],\n  \"count\": 1\n}\n"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "add", "1", "Test", "--criterion", KEY, "--input", "run the suite")
    cli("edge", "add", "1", "n1", "n2")
  end

  def output_file(text = OUTPUT) = File.join(@home, "output.json").tap { |path| File.binwrite(path, text) }

  def finish_first(*options)
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "built", *options)
  end

  def claim_second(*options) = cli("node", "claim", "1", "n2", *options)

  def packet = JSON.parse(claim_second("--json").out).dig("result", "packet")

  def test_the_json_claim_carries_the_node_in_the_packet
    finish_first

    assert_equal({ "id" => "n2", "title" => "Test", "kind" => "work", "state" => "claimed" }, packet.fetch("node"))
  end

  def test_the_packet_names_the_criterion_by_key_and_text
    finish_first

    assert_equal({ "key" => KEY, "text" => CRITERION }, packet.fetch("criterion"))
  end

  def test_the_packet_carries_the_input_of_the_node
    finish_first

    assert_equal "run the suite", packet.fetch("input")
  end

  def test_the_packet_carries_the_output_of_each_needed_node_as_json
    finish_first("--output", output_file)

    assert_equal [{ "id" => "n1", "title" => "Build", "output" => { "files" => ["a.rb"], "count" => 1 } }], packet.fetch("needs")
  end

  def test_a_needed_node_with_no_output_carries_null
    finish_first

    assert_equal [{ "id" => "n1", "title" => "Build", "output" => nil }], packet.fetch("needs")
  end

  def test_a_node_that_needs_nothing_carries_an_empty_list_of_needs
    assert_equal [], JSON.parse(cli("node", "claim", "1", "n1", "--json").out).dig("result", "packet", "needs")
  end

  def test_the_text_claim_prints_the_criterion_text_and_the_output_of_each_needed_node
    finish_first("--output", output_file)
    lines = claim_second.out.lines.map(&:chomp)

    assert_equal ["node: n2 Test", "criterion: works", "criterion text: It works", "input: run the suite", "needs: n1 {\"files\":[\"a.rb\"],\"count\":1}"], lines.first(5)
  end

  def test_the_text_claim_says_a_needed_node_has_no_output
    finish_first

    assert_includes claim_second.out, "needs: n1 no output\n"
  end

  def test_the_claim_keeps_its_next_line_beside_the_packet
    finish_first
    result = JSON.parse(claim_second("--json").out)

    assert_equal "plastic node done 1 n2 TEXT", result.fetch("next")
  end

  def test_a_refused_claim_carries_no_packet
    result = JSON.parse(cli("node", "claim", "1", "n2", "--json").out)

    assert_nil result.dig("result", "packet")
  end

  def rule(text, *options) = cli("intent", "rule", "1", text, *options)

  def write_constraints(*items)
    write("#{retrieval.intent("1").dir}/spec.md", keyed_spec({ KEY => CRITERION }) + "\n## Constraints\n" + items.map { |item| "- #{item}\n" }.join)
    cli("sync", "up")
  end

  def test_the_packet_carries_the_rulings_in_force_and_leaves_superseded_ones_out
    finish_first
    rule("Old")
    rule("New", "--supersedes", "D1")
    rule("Other")

    assert_equal [{ "id" => "D2", "text" => "New" }, { "id" => "D3", "text" => "Other" }], packet.fetch("rulings")
  end

  def test_the_packet_carries_the_constraints_of_the_spec
    finish_first
    write_constraints("No new gem", "Keep it plain")

    assert_equal ["No new gem", "Keep it plain"], packet.fetch("constraints")
  end

  def test_a_packet_with_no_rulings_and_no_constraints_carries_empty_lists
    finish_first
    claimed = packet

    assert_equal [[], [], {}], [claimed.fetch("rulings"), claimed.fetch("constraints"), claimed.fetch("omitted")]
  end

  def test_the_text_claim_prints_each_ruling_in_force_and_each_constraint
    finish_first
    rule("Old")
    rule("New", "--supersedes", "D1")
    write_constraints("No new gem")
    lines = claim_second.out.lines.map(&:chomp)

    assert_equal ["ruling: D2 New", "constraint: No new gem"], lines.grep(/\A(ruling|constraint):/)
  end

  def test_the_packet_rulings_are_the_ones_the_brief_prints_without_the_superseded
    finish_first
    rule("Old")
    rule("New", "--supersedes", "D1")
    brief = cli("intent", "brief", "1").out.lines.map(&:chomp).grep(/\Aruling:/).reject { |line| line.end_with?("(superseded)") }

    assert_equal brief, claim_second.out.lines.map(&:chomp).grep(/\Aruling:/)
  end

  def test_the_packet_keeps_the_newest_twenty_rulings_and_counts_the_rest
    finish_first
    22.times { |number| rule("Ruling #{number}") }

    claimed = packet

    assert_equal [20, "D22", { "rulings" => 2 }], [claimed.fetch("rulings").size, claimed.fetch("rulings").last.fetch("id"), claimed.fetch("omitted")]
  end

  def test_the_text_claim_says_how_many_rulings_it_left_out
    finish_first
    22.times { |number| rule("Ruling #{number}") }

    assert_includes claim_second.out, "omitted: 2 rulings; plastic intent brief 1 lists them all\n"
  end
end
