# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/graph_file"

# GraphFile (intent 334, n2): graph.md's four sections, the ## Status writer,
# and the ## Decisions appender. Both writers refuse a cyclic graph and both
# go through AtomicWrite (fold D19r).
class GraphFileTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("graph-file")
    @path = File.join(@dir, "graph.md")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(content)
    File.write(@path, content)
  end

  BASE = <<~MD
    # Graph: Demo

    ## Goal
    Ship it.

    ## Decisions
    - D1 pick approach

    ## Graph
    - n1 needs nothing
    - n2 needs n1

    ## Status
    | Node | State | Detail |
    | --- | --- | --- |
    | n1 | planned |  |
    | n2 | planned |  |
  MD

  # --- split into sections, fence-aware ---------------------------------------

  def test_fenced_heading_does_not_split
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ```text
      ## Graph
      this looks like a heading but is inside a fence
      ```

      ## Graph
      - n1 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
      | n1 | planned |  |
    MD
    result = GraphFile.parse(@path)
    assert_includes result[:decisions], "this looks like a heading but is inside a fence"
    refute_includes result[:decisions], "n1 needs nothing"
    assert_includes result[:graph][:nodes], "n1"
  end

  # --- require the sections ---------------------------------------------------

  def test_missing_graph_section_is_an_error
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach
    MD
    result = GraphFile.parse(@path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("Graph") })
  end

  def test_graph_section_with_no_nodes_is_an_error
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      Nothing declared here, only prose.
    MD
    result = GraphFile.parse(@path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("no nodes") })
  end

  # --- verify: none directive --------------------------------------------------

  def test_verify_none_requires_a_reason
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing
      - verify: none
    MD
    result = GraphFile.parse(@path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("reason") })
  end

  def test_directive_is_stripped_before_edge_parsing
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing
      - verify: none reason=nothing needs a verifier
    MD
    result = GraphFile.parse(@path)
    assert result[:ok], result[:errors].inspect
    assert_equal "nothing needs a verifier", result[:verify][:reason]
    assert_empty result[:graph][:errors]
  end

  # --- write ## Status -----------------------------------------------------------

  def test_status_write_replaces_the_section
    write(BASE)
    rows = [{ node: "n1", state: "done", detail: "x" }, { node: "n2", state: "running", detail: "" }]
    result = GraphFile.write_status(@path, rows)
    assert result[:ok], result[:errors].inspect

    text = File.read(@path)
    assert_equal 1, text.scan(/^## Status$/).length
    assert_includes text, "| n1 | done | x |"
    refute_includes text, "planned"
  end

  def test_status_write_discards_hand_edits
    write(BASE.sub("| n1 | planned |  |", "| n1 | planned |  |\n| hand-edited | fake | row |"))
    rows = [{ node: "n1", state: "done", detail: "" }, { node: "n2", state: "running", detail: "" }]
    GraphFile.write_status(@path, rows)
    text = File.read(@path)
    refute_includes text, "hand-edited"
  end

  def test_write_refuses_a_cyclic_graph
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs n2
      - n2 needs n1

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
      | n1 | planned |  |
      | n2 | planned |  |
    MD
    before = File.read(@path)
    rows = [{ node: "n1", state: "done", detail: "" }]
    result = GraphFile.write_status(@path, rows)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("cyclic") || e.include?("cycle") })
    assert_equal before, File.read(@path), "a refused write must leave the file untouched"
  end

  def test_status_write_creates_a_missing_section
    write(<<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing
    MD
    rows = [{ node: "n1", state: "planned", detail: "" }]
    result = GraphFile.write_status(@path, rows)
    assert result[:ok], result[:errors].inspect
    assert_includes File.read(@path), "## Status"
    assert_equal rows, GraphFile.status_rows(@path)
  end

  def test_status_round_trips_to_the_same_rows
    write(BASE)
    rows = [
      { node: "n1", state: "done", detail: "verdict REVISE, folded" },
      { node: "n2", state: "planned", detail: "" },
    ]
    GraphFile.write_status(@path, rows)
    assert_equal rows, GraphFile.status_rows(@path)
  end

  # --- append a decision -------------------------------------------------------

  def test_append_decision_leaves_other_sections_byte_identical
    write(BASE)
    goal_before = GraphFile.parse(@path)[:goal]
    graph_before = File.read(@path)[/## Graph\n.*?(?=\n## Status)/m]
    status_before = File.read(@path)[/## Status\n.*\z/m]

    result = GraphFile.append_decision(@path, "D2 a new decision")
    assert result[:ok], result[:errors].inspect

    after = File.read(@path)
    assert_equal goal_before, GraphFile.parse(@path)[:goal]
    assert_includes after, graph_before
    assert_includes after, status_before
  end

  def test_append_decision_is_a_list_item
    write(BASE)
    GraphFile.append_decision(@path, "D2 a new decision")
    decisions = GraphFile.parse(@path)[:decisions]
    assert_match(/^- D2 a new decision\s*$/, decisions)
  end
end
