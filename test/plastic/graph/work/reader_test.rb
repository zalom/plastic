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
