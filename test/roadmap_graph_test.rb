# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/roadmap_graph"

# RoadmapGraph (intent 337, n1): reads one roadmap file into the same shape
# the node scope already uses - entries with their INDEX-reconciled status,
# the edge map from "## Graph", the cycle path when one exists, the
# topological batches, the critical paths, and the ready set. Edges come
# from GraphEdges, batches/critical-paths/downstream-hops from ReadySet -
# the ONE parser and the ONE topological sort (327 D1, C1). Matrix rows from
# actions/ACTION_1.md S1/n1. Hermetic: every fixture lives in a
# Dir.mktmpdir; this file never reads or writes the real ~/.plastic.
class RoadmapGraphTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("roadmap-graph")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def roadmap_path
    File.join(@dir, "demo.md")
  end

  def index_path
    File.join(@dir, "INDEX.md")
  end

  def write_roadmap(body)
    File.write(roadmap_path, body)
  end

  def write_index(active: [], future: [], completed: [], abandoned: [])
    index_line = ->(id) { "- [#{id} - Title](store/#{id}--slug/#{id}--slug.md) - 2026-09-09 note." }
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << index_line.call(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << index_line.call(id) }
    lines += ["", "## Abandoned", ""]
    abandoned.each { |id| lines << index_line.call(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << index_line.call(id) }
    File.write(index_path, lines.join("\n") + "\n")
  end

  def basic_roadmap(batches_body, graph_body)
    <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      #{graph_body}
      ## Batches
      #{batches_body}
    MD
  end

  # --- 1.1: edges come from GraphEdges, not a local parser -------------------

  def test_edges_come_from_graph_edges_not_a_local_parser
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_equal({ "101" => [] }, result[:edges])
  end

  # --- 1.2: a cyclic graph returns the whole cycle path, no batches ----------

  def test_cyclic_graph_returns_whole_cycle_path_and_no_batches
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
      - 101 needs 102
      - 102 needs 101
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    refute_nil result[:cycle]
    assert_equal %w[101 102 101], result[:cycle]
    assert_empty result[:batches]
  end

  # --- 1.3: batches match ReadySet.batches for the same edges -----------------

  def test_batches_match_ready_set_batches_for_the_same_edges
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
      - [ ] 103 Third - queued
    B
      - 101 needs nothing
      - 102 needs nothing
      - 103 needs 101 102
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    expected = ReadySet.batches(result[:edges])[:batches]
    assert_equal expected.map(&:sort), result[:batches].map(&:sort)
  end

  # --- 1.4: critical paths match ReadySet.critical_paths ----------------------

  def test_critical_paths_match_ready_set_for_the_same_edges
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
      - [ ] 103 Third - queued
    B
      - 101 needs nothing
      - 102 needs 101
      - 103 needs 102
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    expected = ReadySet.critical_paths(result[:edges])
    assert_equal expected[:critical_path], result[:critical_paths][:critical_path]
    assert_equal expected[:hops], result[:critical_paths][:hops]
  end

  # --- 1.5: INDEX status wins over the roadmap checkbox -----------------------

  def test_index_status_wins_over_the_roadmap_checkbox
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    write_index(completed: ["101"])
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_equal "delivered", result[:entries]["101"][:status]
  end

  # --- 1.6: an entry absent from the graph is merged in as a root ------------

  def test_entry_absent_from_graph_is_merged_in_as_a_root
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_includes result[:entries].keys, "102"
    assert_equal [], result[:edges]["102"]
    refute result[:entries]["102"][:in_graph]
  end

  # --- 1.7: a graph id with no batch entry is reported, not invented ---------

  def test_graph_id_with_no_batch_entry_is_reported_not_invented
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs 999
      - 999 needs nothing
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_includes result[:dangling], "999"
    refute_includes result[:entries].keys, "999"
  end

  # --- 1.8: a roadmap with no ## Graph returns a named reason, no raise ------

  def test_roadmap_without_graph_returns_named_reason_not_raise
    write_roadmap(<<~MD)
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued
    MD
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    refute result[:has_graph]
    refute_nil result[:reason]
  end

  # --- 1.9: no grouping heading is a reported error, not an exception --------

  def test_missing_grouping_heading_is_an_error_not_an_exception
    write_roadmap(<<~MD)
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      - 101 needs nothing
    MD
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    refute_nil result[:reason]
    assert_empty result[:entries]
  end

  # --- 1.10: a need is met only when it is delivered --------------------------

  def test_abandoned_need_does_not_make_an_entry_ready
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - abandoned
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
      - 102 needs 101
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    refute_includes result[:ready], "102"
  end

  # --- 1.11: a fenced example edge is not read as real ------------------------

  def test_fenced_example_edges_are_not_read_as_real
    write_roadmap(<<~MD)
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      - 101 needs nothing

      Example only, not a real edge:
      ```
      - 101 needs 999
      ```

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued
    MD
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_equal({ "101" => [] }, result[:edges])
  end

  # --- 1.12: "## Graph" matches exactly, never by prefix ----------------------

  def test_graph_heading_matches_exactly_not_by_prefix
    write_roadmap(<<~MD)
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued

      ## Graph (superseded 2026-09-01)
      - 101 needs 999
    MD
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    refute result[:has_graph]
  end

  # --- 1.13: an invalid UTF-8 byte does not raise ------------------------------

  def test_invalid_utf8_byte_does_not_raise
    body = basic_roadmap(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    File.open(roadmap_path, "wb") { |f| f.write(body + "\xFF\xFEbad byte\n") }
    result = nil
    assert_silent_of_raise { result = RoadmapGraph.analyze(roadmap_path, index_path: index_path) }
    refute_nil result
  end

  def assert_silent_of_raise
    yield
  rescue StandardError => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end

  # --- 1.14: the model reads no clock or environment seam ---------------------

  def test_library_source_reads_no_clock_or_environment
    source = File.read(File.expand_path("../scripts/lib/roadmap_graph.rb", __dir__))
    refute_match(/\bTime\.now\b/, source)
    refute_match(/\bENV\[/, source)
    refute_match(/\bENV\.fetch\b/, source)
  end

  # --- 1.15: a need on an abandoned entry is reported as a dead end -----------

  def test_need_on_an_abandoned_entry_is_reported_as_a_dead_end
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - abandoned
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
      - 102 needs 101
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_includes result[:dead_ends], "102"
  end

  # --- 1.16: entries within a batch keep roadmap file order -------------------

  def test_entries_within_a_batch_keep_roadmap_file_order
    write_roadmap(basic_roadmap(<<~B, <<~G))
      ### Batch 1
      - [ ] 105 Fifth - queued
      - [ ] 102 Second - queued
      - [ ] 101 First - queued
    B
      - 105 needs nothing
      - 102 needs nothing
      - 101 needs nothing
    G
    result = RoadmapGraph.analyze(roadmap_path, index_path: index_path)
    assert_equal %w[105 102 101], result[:batches].first
  end
end
