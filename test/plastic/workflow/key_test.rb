# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/code_workflow"

class KeyTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def key(text, path) = Plastic::Workflow::Key.parse(text, path)

  def test_a_key_reads_apart_into_its_lane_and_the_segments_of_its_class_path
    parsed = key(:code_close_intent, "Code::Intent::End")

    assert_equal ["code", %w[Code Intent End]], [parsed.lane, parsed.segments]
  end

  def test_a_key_names_the_file_of_its_class_path_in_snake_case
    assert_equal "code/intent/context/check_owner", key(:code_check_context_owner, "Code::Intent::Context::CheckOwner").file
  end

  def test_a_key_finds_its_workflow_class_in_the_namespace
    assert_equal Plastic::Workflows::MoveNode, key(:code_move_node, "MoveNode").workflow_in(Plastic::Workflows)
  end

  def test_a_key_whose_lane_does_not_match_its_class_is_invalid
    error = assert_raises(Plastic::Invalid) { key(:agent_move_node, "MoveNode").workflow_in(Plastic::Workflows) }

    assert_equal "agent_move_node names a agent workflow, and Plastic::Workflows::MoveNode is a code workflow", error.message
  end

  def test_a_class_path_is_walked_one_segment_at_a_time_without_inherit
    source = File.read(File.join(ROOT, "lib", "plastic", "workflow", "key.rb"))

    assert_includes source, "const_get(segment, false)"
    assert_includes source, "const_defined?(segment, false)"
  end

  def test_a_segment_never_resolves_through_the_ancestors_of_its_parent
    namespace = Module.new
    namespace.const_set(:Group, Class.new(Plastic::CodeWorkflow))

    assert_raises(LoadError) { key(:code_group_read, "Group::Read").workflow_in(namespace) }
  end
end
