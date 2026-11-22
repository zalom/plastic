# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/move"
%w[ask done fail impede resolve].each { |name| require_relative "../../../../lib/plastic/commands/node/#{name}" }

class NodeMoveTest < Plastic::TestCase
  Node = Plastic::Commands::Node
  MOVES = [Node::Ask, Node::Done, Node::Fail, Node::Impede, Node::Resolve].freeze

  def test_each_of_the_five_node_commands_is_a_subclass_of_move
    assert_equal [Node::Move], MOVES.map(&:superclass).uniq
  end

  def test_each_takes_the_intent_the_node_and_the_text_as_its_arguments
    assert_equal [%i[intent_id id text]], MOVES.map { |move| move.arguments.map(&:name) }.uniq
  end

  def test_each_keeps_the_text_label_of_its_own
    assert_equal ["the question and what was tried", "what the work showed", "why it failed", "the impediment", "the resolution"], MOVES.map { |move| move.arguments.last.text }
  end

  def test_each_works_on_a_node_of_an_intent
    assert_equal [%i[intent_id id]], MOVES.map(&:subject).uniq
  end

  def test_each_writes_the_work_graph_and_prints_the_intent
    assert_equal [[[:work], [:intent]]], MOVES.map { |move| [move.writes, move.prints] }.uniq
  end

  def test_each_runs_the_workflow_of_its_own
    assert_equal %i[code_ask_node code_done_node code_fail_node code_impede_node code_resolve_node], MOVES.map { |move| move.chain.keys.first }
  end

  def test_only_the_moves_that_give_a_result_take_the_file_option
    names = ->(move) { move.options.map(&:name) }

    assert_equal [[:files]] * 3, [Node::Ask, Node::Fail, Node::Impede].map(&names)
    assert_equal [%i[files output]], [Node::Done].map(&names)
    assert_equal [[]], [Node::Resolve].map(&names).uniq
  end

  def test_move_is_in_no_command_table
    assert_empty Plastic::CLI::TABLE.values.map(&:first).grep(/Move/)
  end
end
