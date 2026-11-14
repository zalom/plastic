# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkReaderTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_intent(title: "Alpha")
  end

  def reader = Plastic::Graph::Work::Reader.new(store_graphs.databases, origin: Plastic::Graph::Origin.new(@plastic_home))

  def plan(*titles) = titles.each { |title| @work.add_node(intent_id: "1", title:) }

  def finish(id)
    @work.claim_node(intent_id: "1", id:, by: "a")
    @work.done_node(intent_id: "1", id:, judge: "tests", findings: "ok")
  end

  def test_an_open_node_with_no_needs_is_ready
    plan("Build")

    assert_equal ["n1"], reader.ready_nodes("1").map(&:id)
  end

  def test_ready_nodes_sort_by_the_number_after_the_prefix
    plan(*(1..10).map { |number| "Step #{number}" })

    assert_equal %w[n1 n2 n3 n4 n5 n6 n7 n8 n9 n10], reader.ready_nodes("1").map(&:id)
  end

  def test_nodes_sort_by_prefix_then_number_then_text_whatever_the_shape_of_the_id
    plan(*(1..6).map { |number| "Step #{number}" })
    ids = %w[n10 12 node-3 a2 n2 n1]
    store_graphs.databases.fetch(:work).transaction do |batch|
      ids.each_with_index { |id, index| batch.add("UPDATE nodes SET id = :id WHERE id = :old", id:, old: "n#{index + 1}") }
    end

    assert_equal %w[12 a2 n1 n2 n10 node-3], retrieval.nodes("1").map(&:id)
  end

  def test_claims_read_in_node_number_order
    plan(*(1..10).map { |number| "Step #{number}" })
    %w[n10 n2].each { |id| @work.claim_node(intent_id: "1", id:, by: "a") }
    claims = Plastic::Graph::Work::Session::Claims.new(store_graphs.databases, store: "global")
    lock = Plastic::Graph::Lock.new(store: "global", intent_id: "1", session_id: "a", mode: "auto", taken_at: nil, renewed_at: nil)

    assert_equal %w[n2 n10], claims.call(lock).map(&:id)
  end

  def test_a_node_waits_until_the_node_it_needs_is_done
    plan("Build", "Test")
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")

    assert_equal ["n1"], reader.ready_nodes("1").map(&:id)
    finish("n1")

    assert_equal ["n2"], reader.ready_nodes("1").map(&:id)
  end

  def test_a_node_reads_by_its_id_and_a_missing_one_reads_nil
    plan("Build")

    assert_equal ["Build", nil], [reader.node("1", "n1").title, reader.node("1", "n2")]
  end

  def test_the_rulings_of_one_intent_leave_out_the_others
    @work.write_intent(title: "Beta")
    @work.add_ruling(intent_id: "1", text: "Ship it")
    @work.add_ruling(intent_id: "2", text: "Wait")

    assert_equal ["Ship it"], reader.rulings("1").map(&:text)
  end

  def test_links_name_the_ref_at_either_end
    @work.add_link(from_ref: "1", to_ref: "2", kind: "chain")
    @work.add_link(from_ref: "3", to_ref: "1", kind: "cites")
    @work.add_link(from_ref: "4", to_ref: "5", kind: "cites")

    assert_equal [%w[1 2], %w[3 1]], reader.links("1").map { |link| [link.from_ref, link.to_ref] }
  end
end
