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
    cli("node", "add", "1", "Test", "--criterion", KEY, "--input", "run the suite", "--input", "docs/b.md")
    cli("edge", "add", "1", "n1", "n2")
  end

  def output_file(text = OUTPUT) = File.join(@home, "output.json").tap { |path| File.binwrite(path, text) }

  def finish_first(*options)
    cli("node", "claim", "1", "n1", "--agent", "tester")
    cli("node", "done", "1", "n1", "built", *options)
  end

  def claim_second(*options) = cli("node", "claim", "1", "n2", "--agent", "tester", *options)

  def packet = JSON.parse(claim_second("--json").out).dig("result", "packet")

  def test_the_json_claim_carries_the_node_in_the_packet
    finish_first

    assert_equal({ "id" => "n2", "title" => "Test", "kind" => "work", "state" => "claimed" }, packet.fetch("node"))
  end

  def test_the_packet_names_the_criterion_by_key_and_text
    finish_first

    assert_equal({ "key" => KEY, "text" => CRITERION }, packet.fetch("criterion"))
  end

  def test_the_packet_carries_the_input_paths_of_the_node_in_order
    finish_first

    assert_equal ["run the suite", "docs/b.md"], packet.fetch("inputs")
  end

  def test_the_packet_has_no_input_key
    finish_first

    refute_includes packet.keys, "input"
  end

  def test_a_node_with_no_input_carries_an_empty_list_of_inputs
    packet = JSON.parse(cli("node", "claim", "1", "n1", "--agent", "tester", "--json").out).dig("result", "packet")

    assert_equal [], packet.fetch("inputs")
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
    assert_equal [], JSON.parse(cli("node", "claim", "1", "n1", "--agent", "tester", "--json").out).dig("result", "packet", "needs")
  end

  def test_the_text_claim_prints_the_criterion_text_and_the_output_of_each_needed_node
    finish_first("--output", output_file)
    lines = claim_second.out.lines.map(&:chomp)

    assert_equal ["node: n2 Test", "criterion: works", "criterion text: It works", "input: run the suite", "input: docs/b.md", "needs: n1 {\"files\":[\"a.rb\"],\"count\":1}"], lines.first(6)
  end

  def test_the_text_claim_says_the_output_is_a_json_file
    assert_includes cli("node", "claim", "1", "n1", "--agent", "tester").out, "output: a JSON file, given with plastic node done 1 n1 TEXT --output PATH\n"
  end

  def test_the_json_packet_says_the_output_is_a_json_file
    result = JSON.parse(cli("node", "claim", "1", "n1", "--agent", "tester", "--json").out)

    assert_equal "a JSON file, given with plastic node done 1 n1 TEXT --output PATH", result.dig("result", "packet", "output")
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
    result = JSON.parse(cli("node", "claim", "1", "n2", "--agent", "tester", "--json").out)

    assert_nil result.dig("result", "packet")
  end
end
