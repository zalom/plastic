require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
# The hook is an extensionless executable; load it so the RetrievalGateHook
# module is defined (the `$PROGRAM_NAME == __FILE__` guard skips the main block).
load File.expand_path("../scripts/hook-retrieval-gate", __dir__)

# Intent 84, Lever 2: the thin executable. Capability-driven branches are tested
# via the extracted RetrievalGateHook.run (DI capabilities + reindex spy), so no
# real qmd/serena is needed. The fail-open and exit-code wiring of the binary
# itself is tested as a subprocess with a controlled (qmd-absent) PATH.
class RetrievalGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-retrieval-gate", __dir__)

  def setup
    @home = Dir.mktmpdir("rg-hook-home")
    @store = File.join(@home, "store")
    @intent_dir = File.join(@store, "84--x")
    FileUtils.mkdir_p(@intent_dir)
    @store_md = File.join(@intent_dir, "spec.md")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def caps(qmd:, qmd_fresh:, serena:)
    { qmd: qmd, qmd_fresh: qmd_fresh, serena: serena }
  end

  def payload(tool_name, tool_input)
    JSON.generate("tool_name" => tool_name, "tool_input" => tool_input)
  end

  # --- run() unit branches ---

  def test_run_blocks_store_md_when_qmd_fresh
    code, err = RetrievalGateHook.run(
      stdin: payload("Read", { "file_path" => @store_md }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    assert_equal 2, code
    assert_includes err, "PLASTIC GATE"
  end

  def test_run_allows_when_qmd_absent
    code, err = RetrievalGateHook.run(
      stdin: payload("Read", { "file_path" => @store_md }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: false, qmd_fresh: false, serena: false)
    )
    assert_equal 0, code
    assert_nil err
  end

  def test_run_stale_allows_and_fires_reindex
    fired = []
    code, err = RetrievalGateHook.run(
      stdin: payload("Read", { "file_path" => @store_md }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: false, serena: false),
      reindex: -> { fired << :hit }
    )
    assert_equal 0, code
    assert_nil err
    assert_equal [:hit], fired
  end

  def test_run_bypass_allows_with_log
    code, err = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => "grep x #{@store_md} # qmd-ok" }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    assert_equal 0, code
    assert_includes err, "bypassed via # qmd-ok"
  end

  def test_run_malformed_stdin_fails_open
    code, err = RetrievalGateHook.run(
      stdin: "not json{{",
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true, serena: false)
    )
    assert_equal 0, code
    assert_nil err
  end

  # --- subprocess: binary wiring + fail-open ---

  # Empty PATH so QmdSync.detect / PowerTools.serena? both report absent: the
  # store .md read is allowed (exit 0). Proves the binary reads stdin, computes
  # real capabilities, and exits cleanly.
  def run_subprocess(stdin, path: "")
    env = { "PATH" => path }
    out = IO.popen(env, ["ruby", SCRIPT, @home], "r+", err: [:child, :out]) do |io|
      io.write(stdin)
      io.close_write
      io.read
    end
    [out, $?]
  end

  def test_subprocess_allows_when_capabilities_absent
    _out, status = run_subprocess(
      payload("Read", { "file_path" => @store_md })
    )
    assert_equal 0, status.exitstatus
  end

  def test_subprocess_malformed_stdin_fails_open
    _out, status = run_subprocess("garbage{{{")
    assert_equal 0, status.exitstatus
  end
end
