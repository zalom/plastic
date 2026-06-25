require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/retrieval_gate"

# Intent 84 Lever 2, redesigned operation-based in intent 89a. Capabilities are
# injected hashes; no real qmd. A Dir.mktmpdir gives a hermetic plastic_home and
# synthetic store paths. Reason String => BLOCK; nil => ALLOW. Only CONTENT SEARCH
# over store markdown is gated; reads and structural ops are always allowed.
class RetrievalGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("retrieval-gate-home")
    @store = File.join(@home, "store")
    @intent_dir = File.join(@store, "84--x")
    FileUtils.mkdir_p(@intent_dir)
    @store_md = File.join(@intent_dir, "spec.md")
    @code_dir = File.join(@home, "code")
    @code_file = File.join(@code_dir, "app.rb")
    @image = File.join(@code_dir, "logo.png")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def caps(qmd:, qmd_fresh:)
    { qmd: qmd, qmd_fresh: qmd_fresh }
  end

  def decide(tool_name:, tool_input:, capabilities:, reindex: -> {}, &blk)
    RetrievalGate.decision(
      tool_name: tool_name, tool_input: tool_input,
      plastic_home: @home, cwd: @home,
      capabilities: capabilities, reindex: reindex, &blk
    )
  end

  # --- reads & structural ops over the store: ALWAYS allowed ---

  def test_read_of_store_md_is_allowed
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @store_md },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason, "reading a known store file is never gated"
  end

  def test_glob_over_store_is_allowed
    reason = decide(
      tool_name: "Glob", tool_input: { "path" => @store, "pattern" => "**/*.md" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason, "filename globbing is structural discovery, not content search"
  end

  def test_bash_cat_store_md_is_allowed
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "cat #{@store_md}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason, "cat is a read, not a content search"
  end

  def test_bash_find_in_store_is_allowed
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "find #{@store} -name savepoint.md" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason, "find is structural discovery, not content search"
  end

  def test_bash_ls_store_is_allowed
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "ls #{@store}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  # --- content search over store markdown: GATED ---

  def test_grep_tool_over_store_blocks_when_fresh
    reason = decide(
      tool_name: "Grep", tool_input: { "pattern" => "needle", "path" => @store },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_bash_grep_store_md_blocks_when_fresh
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{@store_md}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_qmd_stale_allows_search_and_fires_reindex_once
    fired = []
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{@store_md}" },
      capabilities: caps(qmd: true, qmd_fresh: false),
      reindex: -> { fired << :hit }
    )
    assert_nil reason, "stale QMD allows the search this turn"
    assert_equal [:hit], fired, "reindex_async must fire exactly once on stale"
  end

  def test_qmd_absent_allows_search_and_does_not_reindex
    fired = []
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{@store_md}" },
      capabilities: caps(qmd: false, qmd_fresh: false),
      reindex: -> { fired << :hit }
    )
    assert_nil reason
    assert_empty fired, "absent QMD must not reindex"
  end

  # --- code: never hard-gated (Serena is a soft mandate elsewhere) ---

  def test_bash_grep_over_code_is_allowed
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep TODO #{@code_file}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason, "content grep over code is allowed; Serena cannot grep strings"
  end

  def test_read_code_is_allowed
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @code_file },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  def test_grep_tool_over_code_is_allowed
    reason = decide(
      tool_name: "Grep", tool_input: { "pattern" => "TODO", "path" => @code_dir },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  # --- always-allowed ---

  def test_image_allowed
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @image },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  def test_no_targets_allows
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "echo hi | wc" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    # `echo` is not a content-search util; `wc` has no path arg -> no targets -> allow.
    assert_nil reason
  end

  # --- bypass ---

  def test_trailing_qmd_ok_bypasses
    logged = []
    reason = decide(
      tool_name: "Bash",
      tool_input: { "command" => "grep needle #{@store_md} # qmd-ok" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    ) { |sig| logged << sig }
    assert_nil reason, "trailing # qmd-ok bypasses the block"
    assert_equal [:bypass], logged
  end

  def test_quoted_qmd_ok_does_not_bypass
    reason = decide(
      tool_name: "Bash",
      tool_input: { "command" => %(echo "# qmd-ok"; grep needle #{@store_md}) },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    refute_nil reason, "a quoted/echoed # qmd-ok must NOT bypass"
    assert_match(/QMD/i, reason)
  end

  # --- classification: store markdown content search ---

  def test_store_markdown_search_routes_to_qmd_not_serena
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{@store_md}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
    refute_match(/Serena/i, reason)
  end

  def test_non_store_markdown_search_is_allowed
    doc = File.join(@code_dir, "README.md")
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{doc}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  def test_memory_md_non_store_search_is_allowed
    doc = File.join(@home, "memory", "MEMORY.md")
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{doc}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end

  def test_project_store_markdown_search_routes_to_qmd
    dir = File.join(@home, "projects", "plastic", "store", "84--x")
    FileUtils.mkdir_p(dir)
    md = File.join(dir, "spec.md")
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{md}" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_grep_pattern_not_treated_as_path
    # `grep store /tmp/needle.txt` — `store` is the PATTERN, not a path; the only
    # path arg is needle.txt (non-store) -> allow.
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep store /tmp/needle.txt" },
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_nil reason
  end
end
