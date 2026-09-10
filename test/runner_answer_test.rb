# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/runner_answer"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/ready_set"

# RunnerAnswer (intent 340, G7, n6): closes a decision node into graph.md's
# ## Decisions, or unparks a work node the runner parked at `needs_decision`.
# Matrix rows 6.1-6.7 and 6.22 in nodes/n6.md.
class RunnerAnswerTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "answer-fixture"

  def setup
    @root = Dir.mktmpdir("answer-intent")
    @dir = File.join(@root, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  # --- fixture helpers -----------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick an approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Fixture

      ## Goal
      #{goal}

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_work_node(node, files: ["scripts/lib/foo.rb"], budget: 100_000)
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: work
      files: #{files.inspect}
      budget: #{budget}
      ---
      # #{node} - a work node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def write_decision_node(node)
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: decision
      files: []
      budget: 20000
      ---
      # #{node} - a decision to make

      ## Question
      Which approach should this take?
    MD
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def running_line(node, holder: "h", packet: "p1")
    line(node, "running", holder: holder, expires: "2026-01-01T01:00:00Z", packet: packet, model: "sonnet")
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def savepoint_content
    File.exist?(savepoint_path) ? File.read(savepoint_path) : ""
  end

  def graph_path
    File.join(@dir, "graph.md")
  end

  def build_context
    loaded = ReadySet.load_graph(@dir)
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @root, session: nil,
      worktree: nil, worktree_branch: nil,
      graph: loaded.merge(ok: true), errors: []
    )
  end

  # --- 6.1: the decision text lands in graph.md ## Decisions -----------------

  def test_answer_appends_to_graph_decisions
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))

    result = RunnerAnswer.answer(build_context, node: "d1", text: "Use approach B.")

    assert result[:ok], result.inspect
    parsed = GraphFile.parse(graph_path)
    assert_includes parsed[:decisions], "Use approach B."
  end

  # --- 6.2: the decision node closes with verdict=answered --------------------

  def test_answer_writes_done_with_verdict
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))

    result = RunnerAnswer.answer(build_context, node: "d1", text: "Use approach B.")

    assert result[:ok], result.inspect
    assert_equal "done", NodeLedger.status_for_content(savepoint_content, "d1")
    last = NodeLedger.entries_from_content(savepoint_content).select { |e| e[:subject] == "d1" }.last
    assert_equal "answered", last[:fields]["verdict"]
  end

  # --- 6.3: what became ready is printed (returned) ---------------------------

  def test_answer_prints_newly_ready_nodes
    write_graph("- d1 needs nothing\n- n2 needs d1\n")
    write_decision_node("d1")
    write_work_node("n2")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))

    result = RunnerAnswer.answer(build_context, node: "d1", text: "Use approach B.")

    assert result[:ok], result.inspect
    assert_includes result[:newly_ready], "n2"
  end

  # --- 6.4: refuse answer on a work node not parked at needs_decision ---------

  def test_answer_refuses_healthy_work_node
    write_graph("- n2 needs nothing\n")
    write_work_node("n2")
    write_savepoint(line("n2", "planned"))

    result = RunnerAnswer.answer(build_context, node: "n2", text: "retry")

    refute result[:ok]
    assert_equal "not_parked", result[:reason]
    assert_equal "planned", NodeLedger.status_for_content(savepoint_content, "n2")
  end

  # --- 6.4a: unpark a parked work node below the hard cap ---------------------

  def test_answer_unparks_parked_work_node_to_planned
    write_graph("- n2 needs nothing\n")
    write_work_node("n2")
    write_savepoint(
      running_line("n2", packet: "p1") +
      line("n2", "needs_decision", question: "retry?")
    )

    result = RunnerAnswer.answer(build_context, node: "n2", text: "retry it")

    assert result[:ok], result.inspect
    assert_nil result[:respun_to]
    assert_equal "planned", NodeLedger.status_for_content(savepoint_content, "n2")
  end

  # --- 6.4b: respin a parked node at or above the hard attempt cap ------------

  def test_answer_respins_node_at_hard_cap
    write_graph("- n2 needs nothing\n")
    write_work_node("n2")
    cap = ReadySet::DEFAULT_CAPS["work"]
    running = (1..cap).map { |i| running_line("n2", packet: "p#{i}") }.join
    write_savepoint(running + line("n2", "needs_decision", question: "retry?"))

    result = RunnerAnswer.answer(build_context, node: "n2", text: "give up on this attempt")

    assert result[:ok], result.inspect
    refute_nil result[:respun_to]
    assert_equal "superseded", NodeLedger.status_for_content(savepoint_content, "n2")
    assert File.exist?(File.join(@dir, "nodes", "#{result[:respun_to]}.md"))
  end

  # --- 6.4c: the successor inherits body, files and edges ----------------------

  def test_respin_successor_inherits_body_files_and_edges
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_work_node("n1")
    write_work_node("n2", files: ["scripts/lib/bar.rb", "test/bar_test.rb"])
    cap = ReadySet::DEFAULT_CAPS["work"]
    running = (1..cap).map { |i| running_line("n2", packet: "p#{i}") }.join
    write_savepoint(running + line("n2", "needs_decision", question: "retry?"))

    result = RunnerAnswer.answer(build_context, node: "n2", text: "respin it")
    succ = result[:respun_to]

    parsed = NodeFile.parse(File.join(@dir, "nodes", "#{succ}.md"))
    assert_equal "work", parsed[:kind]
    assert_equal ["scripts/lib/bar.rb", "test/bar_test.rb"], parsed[:files]

    sections = NodeFile.split_by_headings(parsed[:body])
    matrix = sections.find { |heading, _| heading.include?(succ) && heading.match?(/matrix/i) }
    refute_nil matrix, "the successor's matrix heading must carry its own id"

    graph = GraphFile.parse(graph_path)
    assert_equal ["n1"], graph[:graph][:edges][succ]
  end

  # --- 6.4d: the superseded line carries by= -----------------------------------

  def test_supersede_line_carries_by_field
    write_graph("- n2 needs nothing\n")
    write_work_node("n2")
    cap = ReadySet::DEFAULT_CAPS["work"]
    running = (1..cap).map { |i| running_line("n2", packet: "p#{i}") }.join
    write_savepoint(running + line("n2", "needs_decision", question: "retry?"))

    result = RunnerAnswer.answer(build_context, node: "n2", text: "respin it")

    last = NodeLedger.entries_from_content(savepoint_content).select { |e| e[:subject] == "n2" }.last
    assert_equal "superseded", last[:state]
    assert_equal result[:respun_to], last[:fields]["by"]
  end

  # --- 6.5: refuse answer on a decision node already done ----------------------

  def test_answer_refuses_already_answered_node
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "done", gates: "answer", verdict: "answered"))
    before = File.read(graph_path)

    result = RunnerAnswer.answer(build_context, node: "d1", text: "a second answer")

    refute result[:ok]
    assert_equal "not_parked", result[:reason]
    assert_equal before, File.read(graph_path)
  end

  # --- 6.6: refuse an empty decision text ---------------------------------------

  def test_answer_refuses_empty_decision
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))
    before = File.read(graph_path)

    result = RunnerAnswer.answer(build_context, node: "d1", text: "   ")

    refute result[:ok]
    assert_equal "empty_answer", result[:reason]
    assert_equal before, File.read(graph_path)
  end

  # --- 6.7: graph.md is written through temp-plus-rename ------------------------

  def test_graph_write_is_atomic
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))
    original = File.read(graph_path)

    assert_raises(RuntimeError) do
      RunnerAnswer.answer(build_context, node: "d1", text: "Use approach B.",
                           renamer: ->(_temp, _target) { raise "boom" })
    end

    assert_equal original, File.read(graph_path)
    assert_equal "needs_decision", NodeLedger.status_for_content(savepoint_content, "d1")
  end

  # --- 6.22: ## Status re-renders after answering -------------------------------

  def test_answer_rerenders_graph_status
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "needs_decision", question: "Which approach?"))

    result = RunnerAnswer.answer(build_context, node: "d1", text: "Use approach B.")

    assert result[:ok], result.inspect
    rows = GraphFile.status_rows(graph_path)
    d1_row = rows.find { |r| r[:node] == "d1" }
    assert_equal "done", d1_row[:state]
  end
end
