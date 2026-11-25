# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"

class NodeClaimSchemaTest < Plastic::TestCase
  include LifecycleHelper

  SCHEMA = "store/1--alpha/resources/tmp/schemas/n1.json"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
  end

  def packet = JSON.parse(cli("node", "claim", "1", "n1", "--agent", "tester", "--json").out).dig("result", "packet")

  def test_a_packet_with_no_schema_file_carries_null
    assert_nil packet.fetch("schema")
  end

  def test_a_packet_names_the_schema_file_of_the_node_by_its_path
    write(SCHEMA, "{\"type\":\"object\"}\n")

    assert_equal store_path(SCHEMA), packet.fetch("schema")
  end

  def test_the_schema_of_another_node_is_not_the_schema_of_this_one
    write("store/1--alpha/resources/tmp/schemas/n2.json", "{}\n")

    assert_nil packet.fetch("schema")
  end

  def test_the_text_claim_prints_the_schema_path_when_the_file_exists
    write(SCHEMA, "{}\n")

    assert_includes cli("node", "claim", "1", "n1", "--agent", "tester").out, "schema: #{store_path(SCHEMA)}\n"
  end

  def test_the_text_claim_prints_no_schema_line_when_there_is_no_file
    refute_includes cli("node", "claim", "1", "n1", "--agent", "tester").out, "schema:"
  end
end
