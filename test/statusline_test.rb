# encoding: UTF-8
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

# Hermetic tests for hooks/statusline (intent 79: per-session resolution via the
# live Bridge). The repo script is run as a subprocess with crafted stdin JSON and
# an isolated HOME + PLASTIC_TMP (Dir.mktmpdir) so nothing touches the real store
# or /tmp. We assert on ANSI-stripped output. Pure-bash dependency injection:
# HOME and PLASTIC_TMP, no monkeypatching, no eval.
class StatuslineTest < Minitest::Test
  STATUSLINE = File.expand_path("../hooks/statusline", __dir__)
  EMDASH = "—"

  def setup
    @home = Dir.mktmpdir("statusline-home")
    @tmp = Dir.mktmpdir("statusline-tmp")
    @cwd = File.join(@home, "apps", "plastic")
    FileUtils.mkdir_p(@cwd)

    @slug = "plastic"
    @project_dir = File.join(@home, ".plastic", "projects", @slug)
    @store = File.join(@project_dir, "store")
    FileUtils.mkdir_p(@store)

    # projects.yml mapping cwd -> this project store, so scope resolves to @slug.
    File.write(File.join(@home, ".plastic", "projects.yml"), <<~YML)
      projects:
        #{@slug}:
          path: "#{@cwd}"
    YML

    # A VERSION file so the version segment renders (keeps the line realistic).
    File.write(File.join(@home, ".plastic", "VERSION"), "1.2.3\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  # --- helpers ---------------------------------------------------------------

  def render(stdin_json)
    out = nil
    IO.popen({ "HOME" => @home, "PLASTIC_TMP" => @tmp },
             [STATUSLINE], "r+") do |io|
      io.write(stdin_json)
      io.close_write
      out = io.read
    end
    out.gsub(/\e\[[0-9;]*m/, "") # strip ANSI
  end

  def stdin_json(session_id: nil)
    payload = {
      "model" => { "display_name" => "Opus" },
      "workspace" => { "current_dir" => @cwd },
      "cwd" => @cwd,
    }
    payload["session_id"] = session_id if session_id
    JSON.generate(payload)
  end

  # Add an active intent to the project INDEX and create its dir + savepoint.
  def add_active_intent(id:, slug:, title:, savepoint_ts: nil)
    index = File.join(@project_dir, "INDEX.md")
    header = File.exist?(index) ? File.read(index) : "## Active\n"
    line = "- [#{id} #{EMDASH} #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md)\n"
    File.write(index, header + line)

    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(intent_dir)
    if savepoint_ts
      File.write(File.join(intent_dir, "savepoint.md"),
                 "#{savepoint_ts}  Why  spec.md created\n")
    end
    intent_dir
  end

  def write_bridge(session_id:, id:, name:, store: @store)
    data = {
      "session" => session_id,
      "intent" => { "id" => id, "dir" => "#{id}--x", "store" => store, "name" => name },
      "build" => { "auto" => true, "stage" => "exec" },
    }
    File.write(File.join(@tmp, "plastic-#{session_id}.json"), JSON.pretty_generate(data))
  end

  # --- cases -----------------------------------------------------------------

  def test_session_bridge_wins_over_newer_savepoint
    # Intent 49 has the NEWEST savepoint (would win the shared heuristic),
    # but THIS session's bridge points at intent 79.
    add_active_intent(id: "49", slug: "other", title: "Other thing",
                      savepoint_ts: "2026-06-22T23:59:59Z")
    add_active_intent(id: "79", slug: "per-session", title: "Per-session statusline via Bridge",
                      savepoint_ts: "2020-01-01T00:00:00Z")

    sid = "sess-A"
    write_bridge(session_id: sid, id: "79", name: "Per-session statusline via Bridge")

    out = render(stdin_json(session_id: sid))
    assert_includes out, "79"
    assert_includes out, "Per-session statusline via Bridge"
    refute_includes out, "49"
    refute_includes out, "Other thing"
  end

  def test_two_sessions_no_crosstalk
    add_active_intent(id: "49", slug: "other", title: "Other thing",
                      savepoint_ts: "2026-06-22T23:59:59Z")

    write_bridge(session_id: "sess-A", id: "79", name: "Alpha intent")
    write_bridge(session_id: "sess-B", id: "49", name: "Beta intent")

    out_a = render(stdin_json(session_id: "sess-A"))
    assert_includes out_a, "79"
    assert_includes out_a, "Alpha intent"
    refute_includes out_a, "Beta intent"

    out_b = render(stdin_json(session_id: "sess-B"))
    assert_includes out_b, "49"
    assert_includes out_b, "Beta intent"
    refute_includes out_b, "Alpha intent"
  end

  def test_falls_back_to_savepoint_when_no_bridge
    add_active_intent(id: "49", slug: "other", title: "Older intent",
                      savepoint_ts: "2020-01-01T00:00:00Z")
    add_active_intent(id: "79", slug: "newer", title: "Newest savepoint",
                      savepoint_ts: "2026-06-22T23:59:59Z")

    # session_id present but NO matching bridge file -> savepoint-recency wins.
    out = render(stdin_json(session_id: "no-bridge-here"))
    assert_includes out, "79"
    assert_includes out, "Newest savepoint"
    refute_includes out, "Older intent"
  end

  def test_no_ruby_or_jq_invoked
    # Strip comments; assert no ruby/jq token survives in executable lines.
    body = File.read(STATUSLINE)
    code = body.each_line.reject { |l| l.strip.start_with?("#") }.join
    refute_match(/\b(ruby|jq)\b/, code,
                 "statusline must not invoke ruby or jq (intent 59 constraint)")
  end
end
