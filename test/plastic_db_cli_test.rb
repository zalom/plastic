require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

# The thin `scripts/plastic-db` CLI (intent 41, ACTION_7): spawns the REAL
# script as a child process against a hermetic tmpdir store, always with an
# explicit --store path and an explicit --session where a verb needs one --
# never the ambient CLAUDE_CODE_SESSION_ID, never a bridge/CWD lookup. The
# CLI is a thin wrapper: every case below round-trips through Plastic::DB,
# never through raw SQL.
class PlasticDbCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/plastic-db", __dir__)

  def setup
    @tmp = Dir.mktmpdir("pdb-tmp")
    @store = Dir.mktmpdir("pdb-store")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@store)
  end

  def cli(*args)
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, CLI, *args, "--store", @store)
  end

  # --- query --status ----------------------------------------------------

  def test_query_status_prints_the_expected_json_set
    out, err, status = cli("status", "1", "active")
    assert status.success?, err

    out, err, status = cli("query", "--status", "active")
    assert status.success?, err
    result = JSON.parse(out)
    assert_equal ["1"], result.map { |h| h["intent_id"] }
  end

  def test_query_status_empty_set_is_an_empty_json_array
    out, err, status = cli("query", "--status", "abandoned")
    assert status.success?, err
    assert_equal [], JSON.parse(out)
  end

  # --- a record verb followed by a query round-trips ----------------------

  def test_record_verb_then_query_round_trips_through_the_cli
    out, err, status = cli("status", "42", "active")
    assert status.success?, err

    out, err, status = cli("query", "--quadrant", "quick_win")
    assert status.success?, err
    assert_equal [], JSON.parse(out), "quadrant not yet set"

    # There is no standalone set_quadrant CLI verb in the terse Q2 surface,
    # so drive it through the session/lease/event verbs instead to prove a
    # second kind of record verb also round-trips.
    out, err, status = cli("lease", "acquire", "42", "--session", "s-a")
    assert status.success?, err
    assert_equal "acquired", out.strip

    out, err, status = cli("lease", "acquire", "42", "--session", "s-b")
    assert status.success?, err
    assert_equal "held", out.strip, "a fresh foreign lease must block a second acquirer"

    out, err, status = cli("lease", "release", "42", "--session", "s-a")
    assert status.success?, err
    assert_equal "released", out.strip

    out, err, status = cli("lease", "acquire", "42", "--session", "s-b")
    assert status.success?, err
    assert_equal "acquired", out.strip, "released lease must be free for a new owner"
  end

  def test_event_then_export_round_trips_through_the_cli
    out, err, status = cli("status", "7", "active")
    assert status.success?, err

    out, err, status = cli("event", "7", "--stage", "Exec", "--type", "progress-note",
                            "--session", "s-1", "--payload", '{"note":"hi"}')
    assert status.success?, err

    intent_dir = Dir.mktmpdir("pdb-intent")
    begin
      out, err, status = cli("export", "7", "--intent-dir", intent_dir)
      assert status.success?, err
      path = out.strip
      assert File.exist?(path)
      lines = File.readlines(path).map { |l| JSON.parse(l) }
      event = lines.find { |l| l["kind"] == "event" }
      assert_equal "progress-note", event["event_type"]
    ensure
      FileUtils.rm_rf(intent_dir)
    end
  end

  def test_session_register_update_end_round_trip
    out, err, status = cli("session", "register", "--session", "sess-cli-1", "--cwd", "/tmp/x", "--intent", "7")
    assert status.success?, err
    row = JSON.parse(out)
    assert_equal "sess-cli-1", row["session_id"]

    out, err, status = cli("session", "update", "--session", "sess-cli-1", "--cwd", "/tmp/y")
    assert status.success?, err
    assert_equal "/tmp/y", JSON.parse(out)["cwd"]

    out, err, status = cli("session", "end", "--session", "sess-cli-1")
    assert status.success?, err
    assert_equal "sess-cli-1", out.strip
  end

  def test_unknown_verb_exits_nonzero
    _out, _err, status = cli("bogus-verb")
    refute status.success?
  end

  # --- bridge (statusline consumer, intent 41 ACTION_12) -----------------

  def test_bridge_prints_empty_output_when_no_session_row_exists
    out, err, status = cli("bridge", "--session", "nobody-armed")
    assert status.success?, err
    assert_equal "", out.strip
  end

  def test_bridge_prints_the_active_intent_for_a_registered_session
    intent_dir = File.join(@store, "store", "41--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "41--demo.md"), "---\nintent: Demo intent title\n---\n\n## Intent\n")

    out, err, status = cli("session", "register", "--session", "sess-br-1", "--cwd", intent_dir, "--intent", "41")
    assert status.success?, err

    out, err, status = cli("bridge", "--session", "sess-br-1")
    assert status.success?, err
    data = JSON.parse(out)
    assert_equal "41", data["intent"]["id"]
    assert_equal "41--demo", data["intent"]["dir"]
    assert_equal "Demo intent title", data["intent"]["name"]
  end
end
