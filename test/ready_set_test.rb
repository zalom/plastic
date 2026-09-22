# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/node_ledger"

# ReadySet (intent 336, n2/n3): the one function that decides what may run.
# Matrix rows from actions/ACTION_1.md n2 (the four readiness conditions,
# named blockers, dead ends, the stale flag) and n3 (batches as topological
# layers, every maximal-length critical path). Hermetic: Dir.mktmpdir
# fixtures, no environment read.
class ReadySetTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("ready-set")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # --- fixture helpers ---------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

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

  def write_node(filename, node:, kind:, files: ["scripts/lib/x.rb"], budget: 100_000, body: nil)
    body ||= default_body(node)
    path = File.join(@dir, "nodes", filename)
    File.write(path, <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
    path
  end

  def default_body(id)
    "# #{id} - a node\n\n## #{id} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n"
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-09-09T10:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  # --- n2: the four readiness conditions ---------------------------------------

  def test_done_node_is_not_ready
    result = ReadySet.ready?(content: line("n1", "done", gates: "g1", commit: "c1"), subject: "n1",
                              graph: { edges: { "n1" => [] } }, nodes: { "n1" => { kind: "work", files: [] } })
    refute result[:ready]
    assert(result[:blockers].any? { |b| b.include?("done") })
  end

  def test_running_node_is_not_ready
    content = line("n1", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc", model: "sonnet")
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } })
    refute result[:ready]
  end

  def test_reclaimed_node_is_ready_again
    content = line("n1", "reclaimed", holder: "auto-1", expired: "2026-09-09T11:00:00Z")
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } })
    assert result[:ready]
  end

  def test_failed_verification_node_is_ready_for_retry
    content = line("n1", "failed_verification", gates: "g1", reason: "broke")
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } })
    assert result[:ready]
  end

  def test_terminal_and_paused_states_are_not_ready
    %w[blocked deferred superseded abandoned needs_decision].each do |state|
      fields = case state
               when "blocked", "deferred", "abandoned" then { reason: "why" }
               when "superseded" then { by: "n9" }
               when "needs_decision" then { question: "what" }
               end
      content = line("n1", state, fields)
      result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                                nodes: { "n1" => { kind: "work", files: [] } })
      refute result[:ready], "expected #{state} to not be ready"
    end
  end

  def test_node_with_no_ledger_line_is_planned
    result = ReadySet.ready?(content: "", subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } })
    assert result[:ready]
  end

  def test_node_with_unfinished_need_is_not_ready
    content = line("n1", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc", model: "sonnet")
    result = ReadySet.ready?(content: content, subject: "n2", graph: { edges: { "n2" => ["n1"] } },
                              nodes: { "n1" => { kind: "work", files: [] }, "n2" => { kind: "work", files: [] } })
    refute result[:ready]
    assert(result[:blockers].any? { |b| b.include?("n1") })
  end

  def test_unattributed_done_does_not_satisfy_a_need
    content = "2026-09-09T10:00:00Z  n1  done gates=g1 commit=c1\n"
    result = ReadySet.ready?(content: content, subject: "n2", graph: { edges: { "n2" => ["n1"] } },
                              nodes: { "n1" => { kind: "work", files: [] }, "n2" => { kind: "work", files: [] } })
    refute result[:ready]
  end

  def test_torn_done_does_not_satisfy_a_need
    content = "2026-09-09T10:00:00Z  n1  done\n" # missing required gates=, so torn
    result = ReadySet.ready?(content: content, subject: "n2", graph: { edges: { "n2" => ["n1"] } },
                              nodes: { "n1" => { kind: "work", files: [] }, "n2" => { kind: "work", files: [] } })
    refute result[:ready]
  end

  def test_superseded_after_done_does_not_satisfy_a_need
    content = line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1") + line("n1", "superseded", by: "n9")
    result = ReadySet.ready?(content: content, subject: "n2", graph: { edges: { "n2" => ["n1"] } },
                              nodes: { "n1" => { kind: "work", files: [] }, "n2" => { kind: "work", files: [] } })
    refute result[:ready]
  end

  def test_ready_touches_no_filesystem_after_the_directory_is_removed
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    analysis = ReadySet.analyze(@dir)
    assert analysis[:ok]
    graph = { edges: { "n1" => [] } }
    nodes = { "n1" => { kind: "work", files: [] } }
    FileUtils.rm_rf(@dir)
    result = ReadySet.ready?(content: "", subject: "n1", graph: graph, nodes: nodes)
    assert result[:ready]
  end

  def test_running_siblings_come_from_the_guarded_content
    graph = { edges: { "n1" => [], "n2" => [] } }
    nodes = { "n1" => { kind: "work", files: ["a.rb"] }, "n2" => { kind: "work", files: ["a.rb"] } }
    before = ReadySet.ready?(content: "", subject: "n1", graph: graph, nodes: nodes)
    assert before[:ready]
    after_content = line("n2", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc",
                                           model: "sonnet")
    after = ReadySet.ready?(content: after_content, subject: "n1", graph: graph, nodes: nodes)
    refute after[:ready]
  end

  def test_file_overlap_with_a_running_sibling_blocks
    graph = { edges: { "n1" => [], "n2" => [] } }
    nodes = { "n1" => { kind: "work", files: ["a.rb"] }, "n2" => { kind: "work", files: ["a.rb"] } }
    content = line("n2", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc",
                                     model: "sonnet")
    result = ReadySet.ready?(content: content, subject: "n1", graph: graph, nodes: nodes)
    refute result[:ready]
  end

  def test_file_overlap_with_no_running_sibling_is_ready
    graph = { edges: { "n1" => [], "n2" => [] } }
    nodes = { "n1" => { kind: "work", files: ["a.rb"] }, "n2" => { kind: "work", files: ["a.rb"] } }
    result = ReadySet.ready?(content: "", subject: "n1", graph: graph, nodes: nodes)
    assert result[:ready]
  end

  def test_a_node_does_not_overlap_itself
    graph = { edges: { "n1" => [] } }
    nodes = { "n1" => { kind: "work", files: ["a.rb"] } }
    result = ReadySet.ready?(content: "", subject: "n1", graph: graph, nodes: nodes)
    assert result[:ready]
  end

  def test_overlap_normalizes_leading_dot_slash_and_trailing_slash
    graph = { edges: { "n1" => [], "n2" => [] } }
    nodes = { "n1" => { kind: "work", files: ["./scripts/x.rb"] },
              "n2" => { kind: "work", files: ["scripts/x.rb/"] } }
    content = line("n2", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc",
                                     model: "sonnet")
    result = ReadySet.ready?(content: content, subject: "n1", graph: graph, nodes: nodes)
    refute result[:ready]
  end

  def test_empty_files_never_overlaps
    graph = { edges: { "n1" => [], "v1" => [] } }
    nodes = { "n1" => { kind: "work", files: [] }, "v1" => { kind: "verify", files: [] } }
    content = line("v1", "running", holder: "auto-1", expires: "2026-09-09T11:00:00Z", input: "abc",
                                     model: "sonnet")
    result = ReadySet.ready?(content: content, subject: "n1", graph: graph, nodes: nodes)
    assert result[:ready]
  end

  def test_attempts_count_running_lines
    entries = NodeLedger.entries_from_content(
      line("n1", "running", holder: "auto-1", expires: "t", input: "p", model: "m") +
      line("n1", "reclaimed", holder: "auto-1", expired: "t") +
      line("n1", "running", holder: "auto-2", expires: "t", input: "p", model: "m") +
      line("n1", "reclaimed", holder: "auto-2", expired: "t")
    )
    assert_equal 2, ReadySet.attempts_count(entries, "n1")
  end

  def test_attempts_reset_at_the_last_terminal_line
    entries = NodeLedger.entries_from_content(
      line("n1", "running", holder: "auto-1", expires: "t", input: "p", model: "m") +
      line("n1", "superseded", by: "n9") +
      line("n1", "running", holder: "auto-2", expires: "t", input: "p", model: "m")
    )
    assert_equal 1, ReadySet.attempts_count(entries, "n1")
  end

  def test_node_reclaimed_past_its_cap_is_not_ready
    content = line("n1", "running", holder: "auto-1", expires: "t", input: "p", model: "m") +
               line("n1", "reclaimed", holder: "auto-1", expired: "t") +
               line("n1", "running", holder: "auto-2", expires: "t", input: "p", model: "m") +
               line("n1", "reclaimed", holder: "auto-2", expired: "t") +
               line("n1", "running", holder: "auto-3", expires: "t", input: "p", model: "m") +
               line("n1", "reclaimed", holder: "auto-3", expired: "t")
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } },
                              caps: { "work" => 3 })
    refute result[:ready]
    assert(result[:blockers].any? { |b| b.include?("cap") })
  end

  def test_node_at_its_cap_is_not_ready
    content = (1..3).map do |i|
      line("n1", "running", holder: "auto-#{i}", expires: "t", input: "p", model: "m")
    end.join
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } }, caps: { "work" => 3 })
    refute result[:ready]
  end

  def test_caps_differ_by_kind
    content = line("r1", "running", holder: "auto-1", expires: "t", input: "p", model: "m") +
               line("r1", "reclaimed", holder: "auto-1", expired: "t") +
               line("r1", "running", holder: "auto-2", expires: "t", input: "p", model: "m")
    result = ReadySet.ready?(content: content, subject: "r1", graph: { edges: { "r1" => [] } },
                              nodes: { "r1" => { kind: "research", files: [] } },
                              caps: ReadySet::DEFAULT_CAPS)
    refute result[:ready], "research's cap of 2 should already be spent"
  end

  def test_caps_are_injectable
    content = (1..3).map do |i|
      line("n1", "running", holder: "auto-#{i}", expires: "t", input: "p", model: "m") +
        line("n1", "reclaimed", holder: "auto-#{i}", expired: "t")
    end.join
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "work", files: [] } }, caps: { "work" => 10 })
    assert result[:ready], "an injected cap of 10 must not be exhausted by 3 attempts"
  end

  def test_failed_verification_count_is_reported_beside_attempts
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_savepoint(line("n1", "failed_verification", gates: "g1", reason: "broke"))
    analysis = ReadySet.analyze(@dir)
    assert_equal 1, analysis[:nodes]["n1"][:failed_verification_count]
    assert_equal 0, analysis[:nodes]["n1"][:attempts]
  end

  def test_failed_verification_count_ignores_torn_lines
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_savepoint("2026-09-09T10:00:00Z  n1  failed_verification\n") # torn: missing gates/reason
    analysis = ReadySet.analyze(@dir)
    assert_equal 0, analysis[:nodes]["n1"][:failed_verification_count]
  end

  def test_dead_end_is_reported_and_never_ready
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_savepoint(line("n1", "abandoned", reason: "cut"))
    analysis = ReadySet.analyze(@dir)
    assert analysis[:nodes]["n2"][:dead_end]
    refute analysis[:nodes]["n2"][:ready]
  end

  def test_dead_end_propagates_through_the_chain
    write_graph("- n1 needs nothing\n- n2 needs n1\n- n3 needs n2\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_node("n3.md", node: "n3", kind: "work", files: [])
    write_savepoint(line("n1", "superseded", by: "n9"))
    analysis = ReadySet.analyze(@dir)
    assert analysis[:nodes]["n3"][:dead_end]
  end

  def test_done_node_is_stale_when_a_need_is_superseded_later
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_savepoint(
      line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1") +
      line("n2", "done", gates: "g1", commit: "c1", holder: "auto-1") +
      line("n1", "superseded", by: "n9")
    )
    analysis = ReadySet.analyze(@dir)
    assert analysis[:nodes]["n2"][:stale]
  end

  def test_need_superseded_then_done_again_is_not_stale
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_savepoint(
      line("n2", "done", gates: "g1", commit: "c1", holder: "auto-1") +
      line("n1", "superseded", by: "n9") +
      line("n1", "reclaimed", holder: "auto-1", expired: "t") +
      line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1")
    )
    analysis = ReadySet.analyze(@dir)
    refute analysis[:nodes]["n2"][:stale]
  end

  def test_stale_uses_file_order_not_timestamps
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    # n2's done line carries a LATER timestamp than n1's supersede, but n1's
    # supersede line comes AFTER n2's done line in file order.
    write_savepoint(
      line("n2", "done", gates: "g1", commit: "c1", holder: "auto-1", ts: "2026-09-09T12:00:00Z") +
      line("n1", "superseded", by: "n9", ts: "2026-09-09T09:00:00Z")
    )
    analysis = ReadySet.analyze(@dir)
    assert analysis[:nodes]["n2"][:stale]
  end

  def test_supersede_before_done_is_not_stale
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_savepoint(
      line("n1", "superseded", by: "n9") +
      line("n2", "done", gates: "g1", commit: "c1", holder: "auto-1")
    )
    analysis = ReadySet.analyze(@dir)
    refute analysis[:nodes]["n2"][:stale]
  end

  def test_a_need_rerun_without_supersede_is_documented_as_not_stale
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    write_savepoint(
      line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1") +
      line("n2", "done", gates: "g1", commit: "c1", holder: "auto-1") +
      line("n1", "reclaimed", holder: "auto-1", expired: "t") +
      line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1", ts: "2026-09-09T13:00:00Z")
    )
    analysis = ReadySet.analyze(@dir)
    refute analysis[:nodes]["n2"][:stale]
  end

  def test_analyze_returns_an_error_result_without_a_graph
    result = ReadySet.analyze(@dir)
    refute result[:ok]
    assert result[:errors].any?
  end

  def test_cyclic_graph_returns_an_error_not_a_hang
    write_graph("- n1 needs n2\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    write_node("n2.md", node: "n2", kind: "work", files: [])
    result = ReadySet.analyze(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("cyc") })
  end

  def test_malformed_node_file_is_an_error_not_a_raise
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    File.write(File.join(@dir, "nodes", "n2.md"), "not a node file at all")
    result = ReadySet.analyze(@dir)
    assert result[:ok], "one malformed node file must not sink the whole analysis"
    assert(result[:errors].any? { |e| e.include?("n2") })
    assert result[:nodes]["n1"]
    refute result[:nodes]["n2"][:ready], "a node with a malformed file must not read as ready"
    assert(result[:nodes]["n2"][:blockers].any? { |b| b.include?("malformed") },
           "the blocker must name the malformed file")
  end

  def test_declared_node_without_a_file_is_reported
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    result = ReadySet.analyze(@dir)
    assert(result[:errors].any? { |e| e.include?("n2") })
    assert_nil result[:nodes]["n2"][:kind]
    refute result[:nodes]["n2"][:ready], "a node declared with no readable file must not read as ready"
    assert(result[:nodes]["n2"][:blockers].any? { |b| b.include?("no nodes/ file") },
           "the blocker must name the unreadable file")
  end

  def test_unknown_kind_gets_the_work_cap_not_no_cap
    content = (1..3).map do |i|
      line("n1", "running", holder: "auto-#{i}", expires: "t", input: "p", model: "m")
    end.join
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => [] } },
                              nodes: { "n1" => { kind: "mystery", files: [] } },
                              caps: ReadySet::DEFAULT_CAPS)
    refute result[:ready], "an unknown kind must still be capped, not skipped"
    assert(result[:blockers].any? { |b| b.include?("cap") })
  end

  def test_nil_kind_falls_back_to_the_work_cap
    # The legacy path (no graph.md at all): nodes is empty, so kind is nil.
    # Finding 1a: this must keep working (335's shipped legacy behavior),
    # bounded by the work cap rather than skipped entirely.
    content = (1..3).map do |i|
      line("n1", "running", holder: "auto-#{i}", expires: "t", input: "p", model: "m")
    end.join
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: {} }, nodes: {},
                              caps: ReadySet::DEFAULT_CAPS)
    refute result[:ready], "nil kind must be capped at the work cap, not left uncapped"
    assert(result[:blockers].any? { |b| b.include?("cap") })
  end

  def test_ready_set_survives_an_invalid_byte_in_the_ledger
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: [])
    bad = "2026-09-09T10:00:00Z  n1  planned \xFF\n".dup.force_encoding("UTF-8")
    write_savepoint(bad)
    result = nil
    assert_silent { result = ReadySet.analyze(@dir) }
    assert result[:ok]
  end

  def test_every_failed_condition_contributes_a_named_blocker
    # All four conditions fail at once: n1's own state is done (not
    # eligible), its need n2 is not done, n2 is running and overlaps n1's
    # own file, and the cap is exhausted at zero.
    content = line("n1", "done", gates: "g1", commit: "c1") +
              line("n2", "running", holder: "auto-1", expires: "t", input: "p", model: "m")
    result = ReadySet.ready?(content: content, subject: "n1", graph: { edges: { "n1" => ["n2"] } },
                              nodes: { "n1" => { kind: "work", files: ["a.rb"] },
                                       "n2" => { kind: "work", files: ["a.rb"] } },
                              caps: { "work" => 0 })
    refute result[:ready]
    assert_equal 4, result[:blockers].length, result[:blockers].inspect
    assert(result[:blockers].any? { |b| b.match?(/eligible/) }, "own-status blocker")
    assert(result[:blockers].any? { |b| b.match?(/needs target n2/) }, "unmet-need blocker")
    assert(result[:blockers].any? { |b| b.match?(/overlap/) }, "file-overlap blocker")
    assert(result[:blockers].any? { |b| b.match?(/cap/) }, "dispatch-cap blocker")
  end

  # --- n3: batches as topological layers, every maximal-length critical path --

  def test_batches_place_a_diamond_join_after_both_arms
    edges = { "a" => [], "b" => ["a"], "c" => ["a"], "d" => %w[b c] }
    result = ReadySet.batches(edges)
    assert result[:ok]
    assert_equal [["a"], %w[b c], ["d"]], result[:batches]
  end

  def test_batches_of_a_chain_are_one_node_each
    edges = { "a" => [], "b" => ["a"], "c" => ["b"] }
    result = ReadySet.batches(edges)
    assert_equal [["a"], ["b"], ["c"]], result[:batches]
  end

  def test_batches_include_every_root
    edges = { "a" => [], "b" => [], "c" => ["a"] }
    result = ReadySet.batches(edges)
    assert_equal %w[a b], result[:batches][0]
  end

  def test_batches_refuse_a_cycle_and_name_its_path
    edges = { "a" => ["b"], "b" => ["a"] }
    result = ReadySet.batches(edges)
    refute result[:ok]
    assert_match(/a.*b|b.*a/, result[:error])
  end

  def test_batch_members_are_sorted_deterministically
    edges = { "z" => [], "a" => [], "m" => [] }
    result = ReadySet.batches(edges)
    assert_equal %w[a m z], result[:batches][0]
  end

  # Fan-in fixture (R-1): two independent roots each feed two mid nodes, both of
  # which feed one join, giving 2 * 2 = 4 maximal paths of length 3.
  FAN_IN_EDGES = {
    "r1" => [], "r2" => [],
    "m1" => %w[r1], "m2" => %w[r1],
    "m3" => %w[r2], "m4" => %w[r2],
    "j"  => %w[m1 m2 m3 m4],
  }.freeze

  def test_every_maximal_path_of_the_fan_in_fixture_is_returned
    result = ReadySet.critical_paths(FAN_IN_EDGES, max_paths: 16)
    assert result[:ok]
    assert_equal 4, result[:total]
    expected = [%w[r1 m1 j], %w[r1 m2 j], %w[r2 m3 j], %w[r2 m4 j]]
    assert_equal expected.sort, result[:paths].sort
  end

  def test_maximal_paths_are_capped_and_the_total_count_is_reported
    result = ReadySet.critical_paths(FAN_IN_EDGES, max_paths: 2)
    assert result[:ok]
    assert_equal 2, result[:paths].length
    assert_equal 4, result[:total]
  end

  def test_max_paths_is_injectable
    result = ReadySet.critical_paths(FAN_IN_EDGES, max_paths: 1)
    assert_equal 1, result[:paths].length
  end

  def test_hops_is_the_node_count
    edges = { "a" => [], "b" => ["a"], "c" => ["b"], "d" => ["c"], "e" => ["d"] }
    result = ReadySet.critical_paths(edges)
    assert_equal 5, result[:hops]
  end

  def test_critical_path_tie_break_is_lexicographic
    edges = { "a" => [], "b" => ["a"], "c" => ["a"], "d" => %w[b c] }
    result = ReadySet.critical_paths(edges)
    assert_equal %w[a b d], result[:critical_path]
  end

  def test_single_node_graph_has_one_path
    result = ReadySet.critical_paths({ "a" => [] })
    assert_equal 1, result[:hops]
    assert_equal [["a"]], result[:paths]
  end

  def test_critical_path_prefers_depth_over_width
    edges = { "root" => [] }
    (1..10).each { |i| edges["wide#{i}"] = ["root"] }
    edges["d1"] = ["root"]
    edges["d2"] = ["d1"]
    edges["d3"] = ["d2"]
    result = ReadySet.critical_paths(edges)
    assert_equal %w[root d1 d2 d3], result[:critical_path]
  end

  def test_critical_path_refuses_a_cycle
    edges = { "a" => ["b"], "b" => ["a"] }
    result = ReadySet.critical_paths(edges)
    refute result[:ok]
    assert result[:error]
  end

  def test_downstream_hops_counts_the_longest_remaining_chain
    edges = { "a" => [], "b" => ["a"], "c" => ["b"] }
    hops = ReadySet.downstream_hops(edges)
    assert_equal 3, hops["a"]
    assert_equal 2, hops["b"]
    assert_equal 1, hops["c"]
  end
end
