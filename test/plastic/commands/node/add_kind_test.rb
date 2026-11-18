# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/add"

class NodeAddKindTest < Plastic::TestCase
  def setup
    super
    alpha_specified
  end

  def kind = store_graphs.retrieval.node("1", "n1").kind

  def test_a_node_added_without_a_kind_is_a_work_node
    ran("node add 1 Build --criterion tests-pass")

    assert_equal "work", kind
  end

  %w[orchestrator work retrieval].each do |name|
    define_method(:"test_a_#{name}_node_keeps_its_kind") do
      ran("node add 1 Build --criterion tests-pass --kind #{name}")

      assert_equal name, kind
    end
  end

  def test_an_unknown_kind_is_refused_and_adds_no_node
    result = line("node add 1 Build --criterion tests-pass --kind colour")

    assert_equal 1, result.code
    assert_includes result.err, "orchestrator, work, retrieval"
    assert_empty store_graphs.retrieval.structure.nodes("1")
  end

  def test_a_node_of_an_old_kind_stays_readable
    ran("node add 1 Build --criterion tests-pass")
    store_graphs.databases.fetch(:store).transaction { |batch| batch.write(:nodes, "UPDATE nodes SET kind = 'test' WHERE id = 'n1'") }

    assert_equal "test", kind
  end
end
