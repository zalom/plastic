require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/retrieval_gate"

# Intent 84, Lever 2: pure decision module. Capabilities are injected hashes; no
# real qmd/serena. A Dir.mktmpdir gives a hermetic plastic_home and synthetic
# store paths. Reason String => BLOCK; nil => ALLOW.
class RetrievalGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("retrieval-gate-home")
    @store = File.join(@home, "store")
    @intent_dir = File.join(@store, "84--x")
    FileUtils.mkdir_p(@intent_dir)
    @store_md = File.join(@intent_dir, "spec.md")
    @code_file = File.join(@home, "code", "app.rb")
    @image = File.join(@home, "code", "logo.png")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def caps(qmd:, qmd_fresh:, serena:)
    { qmd: qmd, qmd_fresh: qmd_fresh, serena: serena }
  end

  def decide(tool_name:, tool_input:, capabilities:, reindex: -> {}, &blk)
    RetrievalGate.decision(
      tool_name: tool_name, tool_input: tool_input,
      plastic_home: @home, cwd: @home,
      capabilities: capabilities, reindex: reindex, &blk
    )
  end

  # --- QMD class ---

  def test_qmd_fresh_blocks_store_md_read
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @store_md },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_qmd_fresh_blocks_store_md_via_bash_grep
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep needle #{@store_md}" },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_qmd_stale_allows_and_fires_reindex_once
    fired = []
    reindex = -> { fired << :hit }
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @store_md },
      capabilities: caps(qmd: true, qmd_fresh: false, serena: false),
      reindex: reindex
    )
    assert_nil reason, "stale QMD allows this turn"
    assert_equal [:hit], fired, "reindex_async must fire exactly once on stale"
  end

  def test_qmd_absent_allows_and_does_not_reindex
    fired = []
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @store_md },
      capabilities: caps(qmd: false, qmd_fresh: false, serena: false),
      reindex: -> { fired << :hit }
    )
    assert_nil reason
    assert_empty fired, "absent QMD must not reindex"
  end

  # --- Serena class ---

  def test_serena_present_blocks_code_read
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @code_file },
      capabilities: caps(qmd: false, qmd_fresh: false, serena: true)
    )
    refute_nil reason
    assert_match(/Serena/i, reason)
  end

  def test_serena_absent_allows_code_read
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @code_file },
      capabilities: caps(qmd: false, qmd_fresh: false, serena: false)
    )
    assert_nil reason
  end

  # --- always-allowed classes ---

  def test_image_allowed_regardless_of_capabilities
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @image },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: true)
    )
    assert_nil reason
  end

  def test_no_targets_allows
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "echo hi | wc" },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: true)
    )
    # `echo` is not a read util; `wc` has no path arg -> no targets -> allow.
    assert_nil reason
  end

  # --- bypass ---

  def test_trailing_qmd_ok_bypasses
    logged = []
    reason = decide(
      tool_name: "Bash",
      tool_input: { "command" => "grep needle #{@store_md} # qmd-ok" },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    ) { |sig| logged << sig }
    assert_nil reason, "trailing # qmd-ok bypasses the block"
    assert_equal [:bypass], logged
  end

  def test_quoted_qmd_ok_does_not_bypass
    reason = decide(
      tool_name: "Bash",
      tool_input: { "command" => %(echo "# qmd-ok"; grep needle #{@store_md}) },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    refute_nil reason, "a quoted/echoed # qmd-ok must NOT bypass"
    assert_match(/QMD/i, reason)
  end

  # --- store markdown beats serena ---

  def test_store_markdown_classified_qmd_not_serena
    # Both QMD and Serena present. Store .md must route to QMD (block w/ QMD reason).
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => @store_md },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
    refute_match(/Serena/i, reason)
  end

  def test_non_store_markdown_is_allowed
    doc = File.join(@home, "code", "README.md")
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => doc },
      capabilities: caps(qmd: false, qmd_fresh: false, serena: true)
    )
    assert_nil reason
  end

  def test_memory_md_non_store_is_allowed
    doc = File.join(@home, "memory", "MEMORY.md")
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => doc },
      capabilities: caps(qmd: false, qmd_fresh: false, serena: true)
    )
    assert_nil reason
  end

  def test_project_store_markdown_classified_qmd
    dir = File.join(@home, "projects", "plastic", "store", "84--x")
    FileUtils.mkdir_p(dir)
    md = File.join(dir, "spec.md")
    reason = decide(
      tool_name: "Read", tool_input: { "file_path" => md },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: true)
    )
    refute_nil reason
    assert_match(/QMD/i, reason)
  end

  def test_grep_pattern_not_treated_as_path
    # `grep store needle.txt` — `store` is the PATTERN, not a path; the only path
    # arg is needle.txt (non-store, non-code). With serena off -> allow.
    reason = decide(
      tool_name: "Bash", tool_input: { "command" => "grep store /tmp/needle.txt" },
      capabilities: caps(qmd: true, qmd_fresh: true, serena: true)
    )
    assert_nil reason
  end
end
