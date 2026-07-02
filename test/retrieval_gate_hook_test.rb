require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
# The hook is an extensionless executable; load it so the RetrievalGateHook
# module is defined (the `$PROGRAM_NAME == __FILE__` guard skips the main block).
load File.expand_path("../scripts/hook-retrieval-gate", __dir__)

# Intent 84 Lever 2, redesigned operation-based (89a). Capability-driven branches
# are tested via the extracted RetrievalGateHook.run (DI capabilities + reindex
# spy). detect_capabilities' three-tier QMD failure model (absent / broken-warn /
# fresh) is tested with injected probes. The fail-open and exit-code wiring of the
# binary itself is tested as a subprocess with a controlled (qmd-absent) PATH.
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

  def caps(qmd:, qmd_fresh:)
    { qmd: qmd, qmd_fresh: qmd_fresh }
  end

  def payload(tool_name, tool_input)
    JSON.generate("tool_name" => tool_name, "tool_input" => tool_input)
  end

  def search_cmd
    "grep needle #{@store_md}"
  end

  # --- run() unit branches ---

  # Intent 108, D8: the retrieval gate is ADVISORY. A gated store search is
  # never denied; the would-block reason ships as additionalContext at exit 0.
  def test_store_content_search_is_advisory_never_denied
    code, err, out = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => search_cmd }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_equal 0, code, "the retrieval gate never denies a read or search (D8)"
    assert_nil err
    parsed = JSON.parse(out)
    context = parsed.dig("hookSpecificOutput", "additionalContext")
    assert_includes context, "qmd"
    assert_includes context.downcase, "advisory"
  end

  def test_non_store_search_stays_silent
    code, _err, out = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => "grep needle #{File.join(@home, 'code', 'app.rb')}" }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_equal 0, code
    assert_nil out
  end

  def test_run_allows_read_of_store_md
    code, err = RetrievalGateHook.run(
      stdin: payload("Read", { "file_path" => @store_md }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_equal 0, code
    assert_nil err
  end

  def test_run_allows_search_when_qmd_absent
    code, err = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => search_cmd }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: false, qmd_fresh: false)
    )
    assert_equal 0, code
    assert_nil err
  end

  def test_run_stale_allows_and_fires_reindex
    fired = []
    code, err = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => search_cmd }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: false),
      reindex: -> { fired << :hit }
    )
    assert_equal 0, code
    assert_nil err
    assert_equal [:hit], fired
  end

  def test_run_bypass_token_still_accepted_silently
    # Backward compatibility: `# qmd-ok` is still accepted, but with nothing to
    # bypass (the gate is advisory) it no longer announces itself.
    code, err, out = RetrievalGateHook.run(
      stdin: payload("Bash", { "command" => "grep x #{@store_md} # qmd-ok" }),
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_equal 0, code
    assert_nil err
    assert_nil out
  end

  def test_run_malformed_stdin_fails_open
    code, err = RetrievalGateHook.run(
      stdin: "not json{{",
      plastic_home: @home, cwd: @home,
      capabilities: caps(qmd: true, qmd_fresh: true)
    )
    assert_equal 0, code
    assert_nil err
  end

  # --- detect_capabilities: three-tier QMD failure model ---

  def test_detect_warns_when_qmd_present_but_probe_breaks
    warned = []
    result = RetrievalGateHook.detect_capabilities(
      cwd: @home,
      detect: -> { true },
      fresh: -> { raise "boom" },
      warn: ->(m) { warned << m }
    )
    assert_equal({ qmd: false, qmd_fresh: false }, result,
                 "a broken probe degrades to allow this turn")
    assert_equal 1, warned.length, "tier-b emits exactly one warn"
    assert_match(/QMD/i, warned.first)
  end

  def test_detect_does_not_warn_when_qmd_absent
    warned = []
    result = RetrievalGateHook.detect_capabilities(
      cwd: @home,
      detect: -> { false },
      fresh: -> { raise "fresh must not be probed when qmd is absent" },
      warn: ->(m) { warned << m }
    )
    assert_equal({ qmd: false, qmd_fresh: false }, result)
    assert_empty warned, "absent QMD is not a tier-b breakage"
  end

  def test_detect_reports_fresh_when_probe_succeeds
    result = RetrievalGateHook.detect_capabilities(
      cwd: @home, detect: -> { true }, fresh: -> { true }, warn: ->(_m) {}
    )
    assert_equal({ qmd: true, qmd_fresh: true }, result)
  end

  # --- subprocess: binary wiring + fail-open ---

  # Empty PATH so QmdSync.detect reports absent: the store .md search is allowed
  # (exit 0). Proves the binary reads stdin, computes real capabilities, exits clean.
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
      payload("Bash", { "command" => search_cmd })
    )
    assert_equal 0, status.exitstatus
  end

  def test_subprocess_malformed_stdin_fails_open
    _out, status = run_subprocess("garbage{{{")
    assert_equal 0, status.exitstatus
  end
end
