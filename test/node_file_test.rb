# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/node_file"

# NodeFile (intent 334, n3): the envelope (node, kind, files, budget) and the
# minter. Pure and dependency-injected: parse takes a path, never raises
# across the boundary, and returns the Result-hash shape every library in
# scripts/lib/ returns.
class NodeFileTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("node-file")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(basename, content)
    path = File.join(@dir, basename)
    File.write(path, content)
    path
  end

  VALID_BODY = <<~MD
    # n1 - a work node

    ## Steps
    1. do it

    ## Proven by
    (filled at close)
  MD

  def valid_envelope(node: "n1", kind: "work", files: ["scripts/lib/x.rb"], budget: 100_000)
    files_yaml = files.nil? ? "" : "files: #{files.inspect}\n"
    <<~MD
      ---
      node: #{node}
      kind: #{kind}
      #{files_yaml}budget: #{budget}
      ---
      #{VALID_BODY}
    MD
  end

  # --- parse the envelope -----------------------------------------------------

  def test_missing_frontmatter_is_an_error
    path = write("n1.md", "# n1 - no frontmatter at all\n\n## Steps\n1. x\n")
    result = NodeFile.parse(path)
    refute result[:ok]
    refute_empty result[:errors]
  end

  def test_non_mapping_frontmatter_is_an_error
    path = write("n1.md", "---\n- one\n- two\n---\n\n# n1\n")
    result = NodeFile.parse(path)
    refute result[:ok]
    refute_empty result[:errors]
  end

  # --- read kind ---------------------------------------------------------------

  def test_unknown_kind_is_an_error
    path = write("n1.md", valid_envelope(kind: "mystery"))
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("kind") })
  end

  # --- read node -----------------------------------------------------------------

  def test_id_must_match_filename
    path = write("n2.md", valid_envelope(node: "n1"))
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("filename") })
  end

  def test_filename_slug_suffix_is_accepted_exactly
    path = write("n1--graph-edges.md", valid_envelope(node: "n1"))
    result = NodeFile.parse(path)
    assert result[:ok], result[:errors].inspect

    # A loose accept would let a longer id's file satisfy a shorter one.
    path2 = write("n11--other.md", valid_envelope(node: "n1"))
    result2 = NodeFile.parse(path2)
    refute result2[:ok]
  end

  # --- check the id prefix -------------------------------------------------------

  def test_id_prefix_must_match_kind
    path = write("n7.md", valid_envelope(node: "n7", kind: "verify"))
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("kind") || e.include?("prefix") })
  end

  # --- budget ----------------------------------------------------------------------

  def test_turns_budget_is_an_error
    path = write("n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: ["scripts/lib/x.rb"]
      budget: {turns: 40}
      ---
      #{VALID_BODY}
    MD
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("turns") })
  end

  def test_budget_forms_normalize_to_tokens
    bare = write("n1.md", valid_envelope(budget: 120_000))
    result_bare = NodeFile.parse(bare)
    assert_equal 120_000, result_bare[:budget]

    dir2 = Dir.mktmpdir("node-file-2")
    begin
      path = File.join(dir2, "n1.md")
      File.write(path, <<~MD)
        ---
        node: n1
        kind: work
        files: ["scripts/lib/x.rb"]
        budget: {tokens: 120000}
        ---
        #{VALID_BODY}
      MD
      result_hash = NodeFile.parse(path)
      assert_equal 120_000, result_hash[:budget]
    ensure
      FileUtils.rm_rf(dir2)
    end
  end

  # --- depends_on ----------------------------------------------------------------

  def test_depends_on_in_envelope_is_an_error
    path = write("n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: ["scripts/lib/x.rb"]
      budget: 100000
      depends_on: [v1]
      ---
      #{VALID_BODY}
    MD
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("depends_on") })
  end

  # --- files -----------------------------------------------------------------------

  def test_files_must_be_a_list
    path = write("n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: scripts/lib/x.rb
      budget: 100000
      ---
      #{VALID_BODY}
    MD
    result = NodeFile.parse(path)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("files") })
  end

  # --- body sections -----------------------------------------------------------------

  def test_heading_inside_fence_is_not_a_section
    body = <<~MD
      # n1 - fenced

      ```markdown
      ## Proven by
      not a real section
      ```

      ## Steps
      1. do it
    MD
    path = write("n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: ["scripts/lib/x.rb"]
      budget: 100000
      ---
      #{body}
    MD
    result = NodeFile.parse(path)
    sections = NodeFile.split_by_headings(result[:body]).map { |heading, _body| heading }
    refute_includes sections, "## Proven by"
    assert_includes sections, "## Steps"
  end

  # --- mint_id -----------------------------------------------------------------------

  def test_mint_id_skips_taken_ids
    assert_equal "n2", NodeFile.mint_id("work", %w[n1])
  end

  # Intent 335a, owner ruling 2026-09-09: node ids NEVER recycle. This test was
  # `test_mint_id_after_a_gap` and asserted "n2", the lowest free id. Intent 335
  # keyed the work ledger on node id, so a reissued id silently inherits the
  # dead node's transition history, evidence and holder included. The gap is a
  # headstone, not free space.
  def test_mint_id_does_not_fill_a_gap
    assert_equal "n4", NodeFile.mint_id("work", %w[n1 n3])
  end

  def test_mint_id_on_no_taken_ids_is_one
    assert_equal "n1", NodeFile.mint_id("work", [])
    assert_equal "v1", NodeFile.mint_id("verify", [])
  end

  def test_mint_id_is_independent_per_kind
    assert_equal "v1", NodeFile.mint_id("verify", %w[n1 n2 n3])
    assert_equal "n4", NodeFile.mint_id("work", %w[n1 n2 n3 v9])
  end

  def test_mint_id_on_an_unknown_kind_is_nil
    assert_nil NodeFile.mint_id("nope", %w[n1])
  end

  # Spec D11: the gatherer over-reserves on purpose, so the minter is handed ids
  # its own per-kind grammar rejects and must ignore them without shifting.
  def test_mint_id_ignores_ids_that_do_not_match_the_kind_grammar
    assert_equal "n2", NodeFile.mint_id("work", %w[n0 nx n1 Intent v7])
  end

  # 1.8: the file must not still document the rule this intent removed.
  def test_node_file_does_not_document_gap_filling
    path = File.expand_path("../scripts/lib/node_file.rb", __dir__)
    stale = File.readlines(path).each_with_index.filter_map do |line, i|
      "#{i + 1}: #{line.strip}" if line.include?("next free one") ||
                                   line.include?("is filled rather than skipped past")
    end
    assert_empty stale, "node_file.rb still documents the rule 335a removed"
  end

  def test_mint_id_past_ten
    taken = (1..9).map { |i| "n#{i}" }
    assert_equal "n10", NodeFile.mint_id("work", taken)
    assert_equal "n11", NodeFile.mint_id("work", taken + ["n10"])
  end
end
