# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/lines"

class LinesTest < Minitest::Test
  Node = Struct.new(:id, :state, :title, :claimed_by, :deadline)
  Ruling = Struct.new(:id, :text, :supersedes)
  Run = Struct.new(:node_id, :number, :agent, :harness, :session_id, :result, :model, :input_tokens, :output_tokens, :cache_read_tokens,
    :cache_write_tokens, :cost_usd, :worker_session, :usage_note) do
    def open? = result.nil?
  end

  def lines = Plastic::Workflows::Lines

  def test_a_node_line_names_its_state_and_title
    assert_equal "node: n1 open Build", lines.node(Node.new(id: "n1", state: "open", title: "Build"))
  end

  def test_a_claimed_node_line_names_its_holder
    assert_equal "node: n1 claimed Build, held by s-1", lines.node(Node.new("n1", "claimed", "Build", "s-1"))
  end

  def test_a_claimed_node_line_without_a_holder_names_none
    assert_equal "node: n1 claimed Build", lines.node(Node.new("n1", "claimed", "Build"))
  end

  def test_a_node_line_with_a_deadline_names_its_minutes
    assert_equal "node: n1 open Build, deadline 30 minutes", lines.node(Node.new(id: "n1", state: "open", title: "Build", deadline: 30))
  end

  def test_a_node_line_names_the_node_it_was_found_in_before_its_deadline
    assert_equal "node: n2 open Extra, found in n1, deadline 30 minutes", lines.node(Node.new(id: "n2", state: "open", title: "Extra", deadline: 30), "n1")
  end

  def test_a_node_line_with_a_deadline_of_one_minute_says_minute
    assert_equal "node: n1 open Build, deadline 1 minute", lines.node(Node.new(id: "n1", state: "open", title: "Build", deadline: 1))
  end

  def test_one_minute_is_singular_and_any_other_count_is_plural
    assert_equal ["1 minute", "2 minutes", "31 minutes"], [1, 2, 31].map { |count| lines.minutes(count) }
  end

  def test_a_ready_node_line_leaves_out_the_state
    assert_equal "ready: n1 Build", lines.ready_node(Node.new(id: "n1", state: "open", title: "Build"))
  end

  def test_a_superseded_ruling_is_marked
    rulings = [Ruling.new(id: "r1", text: "old"), Ruling.new(id: "r2", text: "new", supersedes: "r1")]

    assert_equal ["ruling: r1 old (superseded)", "ruling: r2 new"], lines.rulings(rulings)
  end

  def test_rulings_print_in_number_order_not_text_order
    rulings = %w[D10 D1 D2].map { |id| Ruling.new(id: id, text: id.downcase) }

    assert_equal ["ruling: D1 d1", "ruling: D2 d2", "ruling: D10 d10"], lines.rulings(rulings)
  end

  def test_a_run_line_names_the_agent_the_harness_the_figures_and_the_worker
    run = Run.new("n1", 2, "a", "codex", "s-1", "done", "gpt-x", 5, 6, 7, 8, 1.5, "w-1", "cost not found")

    assert_equal "run: n1 #2 agent a, codex session s-1, done; gpt-x, 5 in, 6 out, 7 cache read, 8 cache write, $1.50, worker w-1; cost not found", lines.run_line(run)
  end

  def test_a_run_line_with_nothing_recorded_says_none_and_leaves_the_figures_out
    run = Run.new("n1", 1, nil, "", "s-1", nil, nil, nil, nil, nil, nil, nil, nil, nil)

    assert_equal "run: n1 #1 agent none, session s-1, open", lines.run_line(run)
  end
end
