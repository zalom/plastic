# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/action_graph_shim"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/savepoint"

# ActionGraphShim (intent 342, n1): a read-time view that presents
# actions/*.md as a synthetic node graph for any intent directory carrying no
# authored graph.md (spec.md D1-D14). Pure and side-effect-free - nothing is
# ever written to an intent directory, and an authored graph.md always wins
# over the synthetic chain (D3).
class ActionGraphShimTest < Minitest::Test
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

  def setup
    @dir = Dir.mktmpdir("action-graph-shim")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def actions_dir
    File.join(@dir, "actions")
  end

  def write_action(name, body)
    FileUtils.mkdir_p(actions_dir)
    File.write(File.join(actions_dir, name), body)
  end

  def write_graph(edges_text)
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{edges_text}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(id, kind: "work", files: ["scripts/lib/x.rb"], body:)
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: #{files.inspect}
      budget: 100000
      ---
      #{body}
    MD
  end

  # --- resolve realness ----------------------------------------------------

  def test_empty_and_sentinel_action_files_are_not_nodes
    write_action("ACTION_1.md", "")
    write_action("ACTION_2.md", "#{SENTINEL}\n\nplaceholder\n")
    assert_equal :none, ActionGraphShim.shape(@dir)
    assert_equal [], ActionGraphShim.nodes(@dir)
  end

  # --- resolve a missing directory ------------------------------------------

  def test_shape_none_for_missing_dir
    assert_equal :none, ActionGraphShim.shape(File.join(@dir, "no-such-dir"))
    assert_equal [], ActionGraphShim.nodes(File.join(@dir, "no-such-dir"))
  end

  # --- order action files ----------------------------------------------------

  def test_action_files_order_numerically
    write_action("ACTION_2.md", "# two\n")
    write_action("ACTION_10.md", "# ten\n")
    write_action("ACTION_1.md", "# one\n")
    nodes = ActionGraphShim.nodes(@dir)
    assert_equal %w[n1 n2 n3], nodes.map { |n| n[:node] }
    assert_equal "# one\n", nodes[0][:body]
    assert_equal "# two\n", nodes[1][:body]
    assert_equal "# ten\n", nodes[2][:body]
  end

  def test_sort_key_is_total_over_mixed_basenames
    write_action("ACTION-1-bridge-ledger-api.md", "# hyphen\n")
    write_action("ACTION_1_milestone_map.md", "# underscore\n")
    write_action("01-roadmap-queue-reader.md", "# leading-zero\n")
    nodes = ActionGraphShim.nodes(@dir)
    assert_equal 3, nodes.length
    assert_equal %w[n1 n2 n3], nodes.map { |n| n[:node] }
  end

  # --- glob action files -----------------------------------------------------

  def test_non_action_n_basenames_become_nodes
    write_action("ACTION-1-bridge-ledger-api.md", "# a\n")
    write_action("ACTION_1_milestone_map.md", "# b\n")
    write_action("01-roadmap-queue-reader.md", "# c\n")
    assert_equal :actions, ActionGraphShim.shape(@dir)
    assert_equal 3, ActionGraphShim.nodes(@dir).length
  end

  # --- mint node ids -----------------------------------------------------------

  def test_minted_ids_satisfy_node_file_rules
    12.times { |i| write_action("ACTION_#{i + 1}.md", "# #{i + 1}\n") }
    nodes = ActionGraphShim.nodes(@dir)
    assert_equal 12, nodes.length
    nodes.each { |n| assert_match(/\An[1-9][0-9]*\z/, n[:node]) }
  end

  # --- chain edges -------------------------------------------------------------

  def test_chain_is_acyclic_with_one_root
    [1, 2, 7, 14].each do |count|
      dir = Dir.mktmpdir("chain-#{count}")
      begin
        count.times { |i| File.write(File.join(FileUtils.mkdir_p(File.join(dir, "actions")).first, "ACTION_#{i + 1}.md"), "# #{i + 1}\n") }
        view = ActionGraphShim.view(dir)
        edges = view[:graph][:edges]
        roots = edges.select { |_id, targets| targets.empty? }
        assert_equal 1, roots.length, "expected exactly one root for #{count} files"
        assert_equal count, edges.keys.length
        refute view.dig(:graph, :nodes).nil?
        require_relative "../scripts/lib/graph_edges"
        refute GraphEdges.cycle(edges), "synthetic chain must be acyclic for #{count} files"
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  # --- parse the files section -------------------------------------------------

  def test_files_section_spellings_agree
    write_action("ACTION_1.md", <<~MD)
      # Action 1

      ## Files
      - `scripts/lib/a.rb`
      - `test/a_test.rb`
    MD
    write_action("ACTION_2.md", <<~MD)
      # Action 2

      ## Files to touch
      - `scripts/lib/b.rb`
      - `test/b_test.rb`
    MD
    nodes = ActionGraphShim.nodes(@dir)
    assert_equal ["scripts/lib/a.rb", "test/a_test.rb"], nodes[0][:files]
    assert_equal ["scripts/lib/b.rb", "test/b_test.rb"], nodes[1][:files]
  end

  # --- parse a negated files section --------------------------------------------

  def test_negated_files_heading_is_not_a_files_section
    write_action("ACTION_1.md", <<~MD)
      # Action 1

      ## Files in hooks/ you must NOT change
      - `hooks/install.sh`
      - `hooks/uninstall.sh`
    MD
    nodes = ActionGraphShim.nodes(@dir)
    assert_equal [], nodes[0][:files]
    assert nodes[0][:ok]
  end

  # --- extract paths from a files section ---------------------------------------

  def test_files_paths_come_from_tables_and_continuation_lines
    write_action("ACTION_1.md", <<~MD)
      # Action 1

      ## Files

      | Path | Why |
      | --- | --- |
      | `scripts/lib/table.rb` | table cell |

      Also touches
        `scripts/lib/continuation.rb`
    MD
    files = ActionGraphShim.nodes(@dir)[0][:files]
    assert_includes files, "scripts/lib/table.rb"
    assert_includes files, "scripts/lib/continuation.rb"
  end

  # --- emit a record with no declared files -------------------------------------

  def test_missing_files_section_is_ok_with_empty_files
    write_action("ACTION_1.md", "# Action 1\n\nNo files heading anywhere in this body.\n")
    node = ActionGraphShim.nodes(@dir).first
    assert node[:ok]
    assert_equal [], node[:files]
    assert_equal [], node[:errors]
  end

  # --- read Proven-by labels -----------------------------------------------------

  def test_proven_by_requires_an_owned_table
    write_action("ACTION_1.md", <<~MD)
      # Action 1

      ### S1 - a step mentioning S1 in prose only

      No table here, just prose about S1.

      ### S2 - a step with a real matrix

      | Operation | Failure mode | Test |
      | --- | --- | --- |
      | op | mode | a test |
    MD
    node = ActionGraphShim.nodes(@dir).first
    refute_includes node[:proven_by], "S1"
    assert_includes node[:proven_by], "S2"
  end

  # --- resolve the shape ----------------------------------------------------------

  def test_authored_graph_wins_over_actions
    write_graph("- n1 needs nothing\n")
    write_node("n1", body: "# n1 - a work node\n\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n")
    write_action("ACTION_1.md", "# legacy action, must be ignored\n")
    write_action("ACTION_2.md", "# another legacy action, must be ignored\n")

    assert_equal :authored, ActionGraphShim.shape(@dir)
    assert_equal GraphFile.parse(File.join(@dir, "graph.md")), ActionGraphShim.view(@dir)

    nodes = ActionGraphShim.nodes(@dir)
    assert_equal 1, nodes.length
    assert_equal "n1", nodes.first[:node]
  end

  # --- ask for node records on an authored intent ---------------------------------

  def test_nodes_returns_records_for_authored_shape
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1", body: "# n1 - a work node\n\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n")
    write_node("n2", body: "# n2 - a work node\n\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n")
    nodes = ActionGraphShim.nodes(@dir)
    refute_empty nodes
    assert_equal %w[n1 n2], nodes.map { |n| n[:node] }.sort
    assert_equal ["n1"], nodes.find { |n| n[:node] == "n2" }[:needs]
  end

  # --- keep one record shape across both shapes ------------------------------------

  def test_record_key_set_identical_across_shapes
    authored_dir = Dir.mktmpdir("authored")
    actions_only_dir = Dir.mktmpdir("actions-only")
    begin
      File.write(File.join(authored_dir, "graph.md"), <<~MD)
        # Graph: Demo

        ## Goal
        Ship it.

        ## Decisions
        - D1 pick approach

        ## Graph
        - n1 needs nothing

        ## Status
        | Node | State | Detail |
        | --- | --- | --- |
      MD
      FileUtils.mkdir_p(File.join(authored_dir, "nodes"))
      File.write(File.join(authored_dir, "nodes", "n1.md"), <<~MD)
        ---
        node: n1
        kind: work
        files: ["scripts/lib/x.rb"]
        budget: 100000
        ---
        # n1 - a work node

        ## Steps
        1. do it

        ## Proven by
        (filled at close)
      MD

      FileUtils.mkdir_p(File.join(actions_only_dir, "actions"))
      File.write(File.join(actions_only_dir, "actions", "ACTION_1.md"), "# Action 1\n\n## Files\n- `scripts/lib/x.rb`\n")

      authored_record = ActionGraphShim.nodes(authored_dir).first
      actions_record = ActionGraphShim.nodes(actions_only_dir).first
      assert_equal authored_record.keys.sort, actions_record.keys.sort
    ensure
      FileUtils.rm_rf(authored_dir)
      FileUtils.rm_rf(actions_only_dir)
    end
  end

  # --- answer needs for an unknown id -----------------------------------------------

  def test_needs_returns_empty_for_unknown_id
    write_action("ACTION_1.md", "# Action 1\n")
    assert_equal [], ActionGraphShim.needs(@dir, "n99")
    assert_equal [], ActionGraphShim.needs(File.join(@dir, "no-such-dir"), "n1")
  end

  # --- read an unreadable action file -------------------------------------------------

  def test_unreadable_action_file_does_not_raise
    write_action("ACTION_1.md", "# real content\n")
    path = File.join(actions_dir, "ACTION_1.md")
    File.chmod(0o000, path)
    begin
      error = nil
      records = nil
      begin
        records = ActionGraphShim.nodes(@dir)
      rescue StandardError => e
        error = e
      end
      assert_nil error, "the shim must never raise on an unreadable action file"
      assert_equal 1, records.length
      refute records.first[:ok]
      refute_empty records.first[:errors]
    ensure
      File.chmod(0o644, path)
    end
  end
end
