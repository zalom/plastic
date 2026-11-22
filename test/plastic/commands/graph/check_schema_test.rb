# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/check"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/remove"

class GraphCheckSchemaTest < Plastic::TestCase
  include LifecycleHelper

  FOLDER = "store/1--alpha/resources/tmp/schemas"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
  end

  def check(*options) = cli("graph", "check", "1", *options)

  def finding = "finding: schema #{FOLDER.delete_prefix("store/1--alpha/")}/n9.json names no live node"

  def test_a_schema_of_a_live_node_is_no_finding
    write("#{FOLDER}/n1.json", "{}\n")

    assert_call check, code: 0, out: /no findings/
  end

  def test_a_schema_that_names_no_node_is_a_finding_that_gives_its_path
    write("#{FOLDER}/n9.json", "{}\n")

    assert_call check, code: 1, out: [finding, "repair: plastic graph show 1"], err: ["plastic: see the findings above"]
  end

  def test_a_schema_of_a_removed_node_is_a_finding
    cli("node", "remove", "1", "n1", "--reason", "no longer needed")
    write("#{FOLDER}/n1.json", "{}\n")

    assert_call check, code: 1, out: /finding: schema resources\/tmp\/schemas\/n1\.json names no live node/, err: ["plastic: see the findings above"]
  end

  def test_the_next_line_offers_the_repair_of_the_schema_finding
    write("#{FOLDER}/n9.json", "{}\n")

    assert_includes check.out, "next: plastic graph show 1\n"
  end

  def test_a_file_that_is_not_json_in_the_schema_folder_is_no_finding
    write("#{FOLDER}/notes.md", "# notes\n")

    assert_call check, code: 0, out: /no findings/
  end

  def test_the_json_answer_carries_the_schema_finding
    write("#{FOLDER}/n9.json", "{}\n")

    assert_includes JSON.parse(check("--json").out).dig("result", "output"), finding
  end
end
