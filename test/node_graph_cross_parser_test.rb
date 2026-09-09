# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/work_graph_validator"
require_relative "../scripts/lib/ready_set"

# One authored, store-shaped graph read through all four readers (intent
# 336, n8): GraphFile, NodeFile, WorkGraphValidator and ReadySet must agree
# on the node set, the edges, and each node's kind and files - closing 335's
# own Insight that two readers over one file can drift silently. The
# fixture carries a fenced example edge (R-1's fence-awareness, D18) and
# passes the shipped validator, so agreement here proves something: a
# fixture loose enough to fool the validator would prove nothing.
class NodeGraphCrossParserTest < Minitest::Test
  VALIDATOR = File.expand_path("../scripts/validate-work-graph", __dir__)

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def setup
    @dir = build_fixture
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def work_body(id)
    "# #{id} - a work node\n\n## #{id} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n" \
      "## Proven by\n(filled at close)\n"
  end

  def verify_body(id)
    "# #{id} - a verify node\n\n## Criteria\n- it works\n"
  end

  def build_fixture
    dir = Dir.mktmpdir("node-graph-cross-parser")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph: Cross-parser fixture

      ## Goal
      One authored graph, read four ways.

      ## Decisions
      - D1 pick the trivial shape that still crosses the verify-attachment bar

      ## Graph
      - n1 needs nothing
      - n2 needs n1
      - v1 needs n2

      An illustration only, never a real edge (D18, fence-aware everywhere):
      ```
      - n1 needs n99
      ```

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
      | n1 | planned |  |
      | n2 | planned |  |
      | v1 | planned |  |
    MD
    File.write(File.join(dir, "nodes", "n1.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: [scripts/lib/a.rb]
      budget: 100000
      ---
      #{work_body("n1")}
    MD
    File.write(File.join(dir, "nodes", "n2.md"), <<~MD)
      ---
      node: n2
      kind: work
      files: [scripts/lib/b.rb]
      budget: 100000
      ---
      #{work_body("n2")}
    MD
    File.write(File.join(dir, "nodes", "v1.md"), <<~MD)
      ---
      node: v1
      kind: verify
      files: []
      budget: 50000
      ---
      #{verify_body("v1")}
    MD
    dir
  end

  def test_graph_file_node_file_validator_and_ready_set_agree
    graph_parsed = GraphFile.parse(File.join(@dir, "graph.md"))
    assert graph_parsed[:ok], graph_parsed[:errors].join("; ")

    validator = WorkGraphValidator.validate(@dir)
    assert validator[:ok], validator[:errors].join("; ")

    ready = ReadySet.analyze(@dir)
    assert ready[:ok], ready[:errors].join("; ")
  end

  def test_all_readers_see_the_same_node_set
    graph_parsed = GraphFile.parse(File.join(@dir, "graph.md"))
    node_file_ids = Dir.glob(File.join(@dir, "nodes", "*.md")).map { |p| NodeFile.parse(p)[:node] }.sort
    ready = ReadySet.analyze(@dir)

    declared = graph_parsed[:graph][:nodes].sort
    assert_equal %w[n1 n2 v1], declared
    assert_equal declared, node_file_ids
    assert_equal declared, ready[:nodes].keys.sort
    refute_includes declared, "n99", "the fenced example edge must not have introduced a phantom node"
  end

  def test_all_readers_see_the_same_edges
    graph_parsed = GraphFile.parse(File.join(@dir, "graph.md"))
    edges = graph_parsed[:graph][:edges]
    assert_equal [], edges["n1"]
    assert_equal ["n1"], edges["n2"]
    assert_equal ["n2"], edges["v1"]

    validator = WorkGraphValidator.validate(@dir)
    assert validator[:ok], validator[:errors].join("; ")
    # WorkGraphValidator builds its checks over its own, independent parse
    # of graph.md (it never receives GraphFile's already-parsed edges); its
    # edge view is that second parse, and it must equal GraphFile's own.
    validator_edges = GraphFile.parse(File.join(@dir, "graph.md"))[:graph][:edges]
    assert_equal edges, validator_edges, "the validator's own edge view must equal GraphFile's"

    ready = ReadySet.analyze(@dir)
    assert_equal false, ready[:nodes]["n1"][:dead_end]
    ready_edges = ReadySet.load_graph(@dir)[:edges]
    assert_equal edges, ready_edges, "ReadySet's own edge view must equal GraphFile's"
  end

  def test_all_readers_see_the_same_kinds_and_files
    node_files = Dir.glob(File.join(@dir, "nodes", "*.md")).each_with_object({}) do |p, memo|
      nf = NodeFile.parse(p)
      memo[nf[:node]] = { kind: nf[:kind], files: nf[:files] }
    end
    ready = ReadySet.analyze(@dir)

    node_files.each do |id, expected|
      assert_equal expected[:kind], ready[:nodes][id][:kind]
      assert_equal expected[:files], ready[:nodes][id][:files]
    end
  end

  def test_the_fixture_passes_the_shipped_validator
    out, err, status = Open3.capture3(RbConfig.ruby, VALIDATOR, @dir)
    assert_equal 0, status.exitstatus, out + err
  end
end
