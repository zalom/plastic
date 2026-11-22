# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/done"
require_relative "../../../test_helpers/two_homes"

class NodeDoneOutputTest < Plastic::TestCase
  include LifecycleHelper

  JSON_TEXT = "{\n  \"files\": [\"a.rb\", \"b.rb\"],\n  \"note\": \"caf\u00e9 \\u2713\"\n}\n"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
  end

  def output_file(text = JSON_TEXT, name: "output.json")
    File.join(@home, name).tap { |path| File.binwrite(path, text) }
  end

  def node = retrieval.node("1", "n1")

  def test_the_json_of_the_file_is_stored_as_the_output_of_the_node
    cli("node", "done", "1", "n1", "built", "--output", output_file)

    assert_equal JSON_TEXT.b, node.output.b
  end

  def test_a_node_finished_with_output_is_done_and_keeps_its_findings
    result = cli("node", "done", "1", "n1", "built", "--output", output_file)

    assert_call result, code: 0, out: /node: n1 done/
    assert_equal %w[done built], [node.state, node.findings]
  end

  def test_a_node_finished_without_the_option_has_no_output
    cli("node", "done", "1", "n1", "built")

    assert_nil node.output
  end

  def test_output_that_is_not_json_exits_1_and_names_node_fail
    result = cli("node", "done", "1", "n1", "built", "--output", output_file("not json"))

    assert_call result, code: 1, out: /next: plastic node fail 1 n1 TEXT/, err: /not JSON/
  end

  def test_output_that_is_not_json_leaves_the_node_claimed_with_no_output
    cli("node", "done", "1", "n1", "built", "--output", output_file("{broken"))

    assert_equal ["claimed", nil], [node.state, node.output]
  end

  def test_a_missing_output_file_exits_1_and_leaves_the_node_claimed
    result = cli("node", "done", "1", "n1", "built", "--output", File.join(@home, "nothing.json"))

    assert_call result, code: 1, out: /plastic node fail/, err: /cannot be read.*nothing\.json/
    assert_equal "claimed", node.state
  end

  def test_the_text_stays_required_beside_the_output_option
    result = cli("node", "done", "1", "n1", "--output", output_file)

    assert_call result, code: 2, err: /TEXT/
    assert_equal "claimed", node.state
  end

  def test_the_usage_line_and_the_help_tell_the_two_file_options_apart
    usage = Plastic::Commands::Node::Done.usage_line("node done")

    assert_includes usage, "--output PATH"
    assert_includes usage, "--file PATH"
  end

  def test_the_option_texts_say_json_for_the_output_and_a_document_for_the_file
    texts = Plastic::Commands::Node::Done.options.to_h { |option| [option.name, option.text] }

    assert_match(/JSON/, texts.fetch(:output))
    assert_match(/intent folder/, texts.fetch(:files))
  end

  def graph_path = store_path("store/1--alpha/graph.json")

  def test_the_graph_file_prints_the_output_and_a_sync_up_keeps_its_bytes
    cli("node", "done", "1", "n1", "built", "--output", output_file)
    printed = File.binread(graph_path)
    cli("sync", "up")

    assert_equal [JSON_TEXT.b, printed], [node.output.b, File.binread(graph_path)]
  end

  def test_a_sync_down_after_a_sync_up_keeps_the_output_bytes_and_the_file
    cli("node", "done", "1", "n1", "built", "--output", output_file)
    printed = File.binread(graph_path)
    cli("sync", "up")
    cli("sync", "down")

    assert_equal [JSON_TEXT.b, printed], [node.output.b, File.binread(graph_path)]
  end
end

# A machine that holds only the files rebuilds the rows from them.
class NodeDoneOutputSecondHomeTest < Minitest::Test
  include TwoHomes

  def test_a_second_home_rebuilds_the_output_from_the_graph_file_with_the_same_bytes
    with_two_homes do |first, second|
      path = File.join(first.home, "output.json")
      File.binwrite(path, NodeDoneOutputTest::JSON_TEXT)
      first.command!("node", "claim", "1", "n2")
      first.command!("node", "done", "1", "n2", "built", "--output", path)
      move_files(first, second)
      second.command!("sync", "up")

      assert_equal [[NodeDoneOutputTest::JSON_TEXT]], query(second, "SELECT output FROM nodes WHERE id = 'n2'")
    end
  end
end
