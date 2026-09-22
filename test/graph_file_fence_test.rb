# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/graph_file"

# GraphFile fence-stripping (intent 336, n6, D18): a fenced example edge
# inside a hand-written graph.md or roadmap ## Graph section must never be
# read as a real edge. Inherited from 334's own fence-aware section location,
# extended here to the edges themselves.
class GraphFileFenceTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("graph-file-fence")
    @path = File.join(@dir, "graph.md")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_graph_section_strips_fenced_blocks_before_edge_parsing
    File.write(@path, <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing

      Example of the grammar, not a real edge:
      ```
      - n1 needs n2
      - n2 needs n1
      ```

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    result = GraphFile.parse(@path)
    assert result[:ok], result[:errors].join("; ")
    assert_equal ["n1"], result[:graph][:nodes]
    assert_equal({ "n1" => [] }, result[:graph][:edges])
  end
end
