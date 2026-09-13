# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/node_ids"
require_relative "../scripts/lib/node_file"

# NodeIds (intent 335a): every id an intent has ever seen, gathered from the
# three places one can appear, so a deleted node's id is never reissued.
# Matrix rows 2.1 to 2.18 of actions/ACTION_1.md.
class NodeIdsTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @dir = Dir.mktmpdir("node-ids")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def write_node(name, node: nil, kind: "work", raw: nil)
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    path = File.join(@dir, "nodes", name)
    if raw
      File.write(path, raw)
    else
      File.write(path, <<~MD)
        ---
        node: #{node}
        kind: #{kind}
        files: []
        budget: 1000
        ---
        # #{node}
      MD
    end
    path
  end

  def write_graph(graph_section, decisions: "")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_section}

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
      | n99 | planned |  |
    MD
  end

  def write_savepoint(text)
    File.write(File.join(@dir, "savepoint.md"), text)
  end

  # --- 2.1 to 2.4: the ledger source ---------------------------------------------

  def test_taken_includes_a_ledger_subject_with_no_node_file
    write_node("n1.md", node: "n1")
    write_savepoint(<<~L)
      2026-09-08T17:00:00Z  n5  running holder=h expires=2030-01-01T00:00:00Z input=p model=m
      2026-09-08T17:01:00Z  n5  done holder=h gates=suite commit=abc
    L
    assert_includes NodeIds.taken(@dir), "n5"
  end

  # The realistic false positive, verbatim from intent 335's own ledger: a node
  # id inside a milestone's free text. A token scan takes "v2" here and mints
  # v3 for the next verify node.
  def test_a_node_id_inside_a_milestone_line_is_not_gathered
    write_savepoint(<<~L)
      2026-09-08T17:05:22Z  Review  plan review 2026-09-08 opus: REVISE, 10 matrix gaps, merged into spec D6 D9 D12 D13 D16-D20 and ACTION_1 v2
      2026-09-08T17:26:19Z  Commit  476235a S1 GuardedAppend, 15/15 matrix tests green
    L
    assert_equal [], NodeIds.taken(@dir)
  end

  def test_a_torn_transition_line_still_reserves_its_subject
    write_savepoint("2026-09-08T17:00:00Z  n7  runn\n")
    assert_includes NodeIds.taken(@dir), "n7"
  end

  def test_the_intent_subject_is_not_gathered_as_a_node_id
    write_savepoint("2026-09-08T17:00:00Z  Intent  running holder=h expires=x input=p model=m\n")
    refute_includes NodeIds.taken(@dir), "Intent"
  end

  # --- 2.5 to 2.9: the nodes/ source ---------------------------------------------

  def test_taken_includes_every_node_file
    write_node("n1.md", node: "n1")
    write_node("n2.md", node: "n2")
    assert_equal %w[n1 n2], NodeIds.taken(@dir)
  end

  # The store's dominant shape: all eight of intent 334's node files are slugged.
  def test_a_slugged_node_filename_reserves_its_id
    write_node("n1--graph-edges.md", node: "n1")
    assert_includes NodeIds.taken(@dir), "n1"
  end

  def test_an_empty_node_file_still_reserves_its_id
    write_node("n3.md", raw: "")
    assert_includes NodeIds.taken(@dir), "n3"
  end

  def test_taken_includes_both_the_filename_and_the_envelope_id
    write_node("n2.md", node: "n7")
    taken = NodeIds.taken(@dir)
    assert_includes taken, "n2"
    assert_includes taken, "n7"
  end

  def test_a_node_file_with_unparseable_frontmatter_still_reserves_its_filename_id
    write_node("n7--broken.md", raw: "---\nnode: [unclosed\nkind: work\n---\n# broken\n")
    assert_includes NodeIds.taken(@dir), "n7"
  end

  # --- 2.10 to 2.11: the graph.md source ------------------------------------------

  def test_taken_includes_graph_declared_and_targeted_nodes
    write_graph("- n1 needs nothing\n      - n2 needs n1\n      - v1 needs n1 n2")
    taken = NodeIds.taken(@dir)
    %w[n1 n2 v1].each { |id| assert_includes taken, id }
  end

  def test_only_the_graph_section_contributes_ids
    write_graph("- n1 needs nothing",
                decisions: "- a decision line that also says d9 needs bogus, and must never be read")
    refute_includes NodeIds.taken(@dir), "d9"
    refute_includes NodeIds.taken(@dir), "bogus"
  end

  # --- 2.12 to 2.14: each absent source, guarded separately -------------------------

  def test_taken_on_a_missing_nodes_directory_is_not_an_error
    write_graph("- n1 needs nothing")
    write_savepoint("")
    assert_includes NodeIds.taken(@dir), "n1"
  end

  def test_taken_on_a_missing_graph_md_is_not_an_error
    write_node("n1.md", node: "n1")
    write_savepoint("")
    assert_equal ["n1"], NodeIds.taken(@dir)
  end

  def test_taken_on_a_missing_savepoint_is_not_an_error
    write_node("n1.md", node: "n1")
    write_graph("- n1 needs nothing")
    assert_equal ["n1"], NodeIds.taken(@dir)
  end

  def test_taken_on_an_empty_directory_is_empty
    assert_equal [], NodeIds.taken(@dir)
  end

  # --- 2.15 to 2.16: composing with the minter --------------------------------------

  def test_mint_id_over_taken_never_reissues_a_deleted_id
    write_node("n1.md", node: "n1")
    write_node("n3.md", node: "n3")
    write_graph("- n1 needs nothing\n      - n3 needs n1")
    write_savepoint(<<~L)
      2026-09-08T17:00:00Z  n2  running holder=h expires=2030-01-01T00:00:00Z input=p model=m
      2026-09-08T17:01:00Z  n2  done holder=h gates=suite commit=abc
    L
    # n2's file is gone; its ledger history is not. Minting must not reissue n2.
    assert_equal "n4", NodeFile.mint_id("work", NodeIds.taken(@dir))
  end

  def test_taken_output_is_safe_to_hand_straight_to_mint_id
    write_node("n1.md", node: "n1")
    write_savepoint("2026-09-08T17:00:00Z  n0  planned\n2026-09-08T17:01:00Z  zz9  planned\n")
    taken = NodeIds.taken(@dir)
    assert_equal "n2", NodeFile.mint_id("work", taken)
    assert_equal "v1", NodeFile.mint_id("verify", taken)
  end

  def test_taken_is_sorted_and_deduplicated
    write_node("n2.md", node: "n2")
    write_graph("- n2 needs nothing\n      - n1 needs nothing")
    write_savepoint("2026-09-08T17:00:00Z  n2  planned\n")
    assert_equal %w[n1 n2], NodeIds.taken(@dir)
  end

  # --- 2.17: load order --------------------------------------------------------------

  def test_node_file_load_set_is_unchanged
    lib = File.join(REPO, "scripts", "lib", "node_file.rb")
    env = { "RUBYOPT" => nil, "CLAUDE_CODE_SESSION_ID" => nil }
    out, err, status = Open3.capture3(env, RbConfig.ruby, "-e",
                                      "require #{lib.inspect}; puts $LOADED_FEATURES")
    assert status.success?, "node_file.rb does not load: #{err}"
    project = out.lines.map(&:strip)
                 .select { |f| f.start_with?("#{REPO}/") }
                 .map { |f| f.sub("#{REPO}/", "") }.sort
    assert_equal %w[scripts/lib/node_file.rb], project,
                 "335a promised NodeFile gains no dependency; it gained one"
  end

  # --- 2.18: packaging ----------------------------------------------------------------

  def test_the_new_file_is_in_the_installer_manifest
    manifest = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    assert_includes manifest, "scripts/lib/node_ids.rb"
  end
end
