# frozen_string_literal: true

require_relative "../test_helper"

class NodeVerbNamesTest < Plastic::TestCase
  def test_the_command_table_names_ask_impede_and_resolve
    assert_equal %w[node\ ask node\ impede node\ resolve], %w[node\ ask node\ impede node\ resolve].select { |name| Plastic::CLI::TABLE.key?(name) }
  end

  def test_the_command_table_has_no_park_answer_or_flag
    assert_empty ["node park", "node answer", "node flag"].select { |name| Plastic::CLI::TABLE.key?(name) }
  end

  def test_node_states_hold_needs_info_and_impeded_and_not_parked
    assert_equal [%w[impeded needs_info], []], [%w[impeded needs_info] & Plastic::Graph::Work::Node::STATES, %w[parked flagged] & Plastic::Graph::Work::Node::STATES]
  end
end
