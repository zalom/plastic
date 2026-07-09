# encoding: UTF-8
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/lib/db"

# Hermetic tests for hooks/statusline (intent 79: per-session resolution).
# Cutover (intent 41 ACTION_12): the statusline used to scan `/tmp/plastic-*.json`
# bridge files directly (bash/grep/sed only, no ruby). It now makes ONE call to
# the `plastic-db bridge` CLI, which resolves the session against the store's
# `plastic.db` (`sessions`/`lock_leases` tables) the same way `Bridge.discover_bridge`
# does, and renders whatever that call prints (empty output on any absence or
# error, falling through to the savepoint-recency scan exactly as a missing
# bridge file used to). The repo script runs as a subprocess with crafted stdin
# JSON and an isolated HOME (Dir.mktmpdir) carrying its own copy of
# scripts/lib + scripts/plastic-db, so nothing touches the real store. Test
# fixtures register sessions directly via Plastic::DB (in-process) for speed;
# only the statusline itself, the thing under test, shells out to the real CLI.
class StatuslineTest < Minitest::Test
  STATUSLINE = File.expand_path("../hooks/statusline", __dir__)
  REPO = File.expand_path("..", __dir__)
  EMDASH = "—"

  def setup
    @home = Dir.mktmpdir("statusline-home")
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

    install_plastic_db_cli
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- helpers ---------------------------------------------------------------

  # Copy this checkout's scripts/lib + scripts/plastic-db into the isolated
  # $HOME/.plastic/scripts, exactly as a real install would place them, so the
  # statusline's one `ruby "$HOME/.plastic/scripts/plastic-db" bridge ...`
  # call resolves against a real, self-contained copy rather than the live
  # ~/.plastic.
  def install_plastic_db_cli
    dest = File.join(@home, ".plastic", "scripts")
    FileUtils.mkdir_p(dest)
    FileUtils.cp_r(File.join(REPO, "scripts", "lib"), dest)
    FileUtils.cp(File.join(REPO, "scripts", "plastic-db"), dest)
  end

  def render(stdin_json)
    out = nil
    IO.popen({ "HOME" => @home }, [STATUSLINE], "r+") do |io|
      io.write(stdin_json)
      io.close_write
      out = io.read
    end
    out.gsub(/\e\[[0-9;]*m/, "") # strip ANSI
  end

  def stdin_json(session_id: nil, cwd: @cwd)
    payload = {
      "model" => { "display_name" => "Opus" },
      "workspace" => { "current_dir" => cwd },
      "cwd" => cwd,
    }
    payload["session_id"] = session_id if session_id
    JSON.generate(payload)
  end

  # Add an active intent to the project INDEX and create its dir + savepoint
  # (the savepoint-recency FALLBACK path, exercised only when no session row
  # resolves a work-unit).
  def add_active_intent(id:, slug:, title:, savepoint_ts: nil)
    index = File.join(@project_dir, "INDEX.md")
    header = File.exist?(index) ? File.read(index) : "## Active\n"
    line = "- [#{id} #{EMDASH} #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md)\n"
    File.write(index, header + line)

    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "#{id}--#{slug}.md"), "---\nintent: #{title}\n---\n\n## Intent\n")
    if savepoint_ts
      File.write(File.join(intent_dir, "savepoint.md"),
                 "#{savepoint_ts}  Why  spec.md created\n")
    end
    intent_dir
  end

  # Register a DB session row for a bare session (no concurrent intents): the
  # statusline's live work-unit source. `id` must name an intent whose
  # directory (and title) already exists under @store (see add_active_intent),
  # since the CLI's bridge verb resolves the display name from the intent's
  # own frontmatter, not from the session row.
  def register_session(session_id:, id:, cwd: nil, now: Time.now)
    intent_dir = Dir.glob(File.join(@store, "#{id}--*")).first
    Plastic::DB.session_register(
      @project_dir, session_id: session_id, host: "test-host", pid: Process.pid,
      cwd: cwd || intent_dir, active_intent_id: id, auto: true, now: now
    )
  end

  # Register one of a bare session's SEVERAL per-intent rows (intent 131
  # convention: `sessions.session_id` is unique, so a session that owns more
  # than one concurrently-armed intent gets one row per intent, keyed
  # "<session>--<intent_id>").
  def register_per_intent_session(session:, id:, cwd:, now: Time.now)
    register_session(session_id: "#{session}--#{id}", id: id, cwd: cwd, now: now)
  end

  # --- cases -----------------------------------------------------------------

  def test_session_row_wins_over_newer_savepoint
    # Intent 49 has the NEWEST savepoint (would win the shared heuristic),
    # but THIS session's own row points at intent 79.
    add_active_intent(id: "49", slug: "other", title: "Other thing",
                      savepoint_ts: "2026-06-22T23:59:59Z")
    add_active_intent(id: "79", slug: "per-session", title: "Per-session statusline via the DB",
                      savepoint_ts: "2020-01-01T00:00:00Z")

    register_session(session_id: "sess-A", id: "79")

    out = render(stdin_json(session_id: "sess-A"))
    assert_includes out, "79"
    assert_includes out, "Per-session statusline via the DB"
    refute_includes out, "49"
    refute_includes out, "Other thing"
  end

  def test_two_sessions_no_crosstalk
    add_active_intent(id: "49", slug: "other", title: "Other thing",
                      savepoint_ts: "2026-06-22T23:59:59Z")
    add_active_intent(id: "79", slug: "alpha", title: "Alpha intent")

    register_session(session_id: "sess-A", id: "79")
    register_session(session_id: "sess-B", id: "49")

    out_a = render(stdin_json(session_id: "sess-A"))
    assert_includes out_a, "79"
    assert_includes out_a, "Alpha intent"
    refute_includes out_a, "Other thing"

    out_b = render(stdin_json(session_id: "sess-B"))
    assert_includes out_b, "49"
    assert_includes out_b, "Other thing"
    refute_includes out_b, "Alpha intent"
  end

  def test_falls_back_to_savepoint_when_no_session_row
    add_active_intent(id: "49", slug: "other", title: "Older intent",
                      savepoint_ts: "2020-01-01T00:00:00Z")
    add_active_intent(id: "79", slug: "newer", title: "Newest savepoint",
                      savepoint_ts: "2026-06-22T23:59:59Z")

    # session_id present but NO matching session row -> savepoint-recency wins.
    out = render(stdin_json(session_id: "no-session-here"))
    assert_includes out, "79"
    assert_includes out, "Newest savepoint"
    refute_includes out, "Older intent"
  end

  def test_falls_back_gracefully_when_plastic_db_is_absent
    # Fail-soft: no plastic-db binary at all (a partial/broken install) must
    # degrade exactly like a missing session row, never crash or hang.
    FileUtils.rm(File.join(@home, ".plastic", "scripts", "plastic-db"))
    add_active_intent(id: "79", slug: "newer", title: "Newest savepoint",
                      savepoint_ts: "2026-06-22T23:59:59Z")

    out = render(stdin_json(session_id: "whatever"))
    assert_includes out, "79"
    assert_includes out, "Newest savepoint"
  end

  def test_cwd_picks_the_right_row_among_a_sessions_several_concurrent_intents
    # Intent 131: a bare session can own SEVERAL concurrently-armed intents
    # (one DB row per intent). cwd inside worktree A's row must select A over
    # a row with a more recent last_seen_at, exercising Sessions.active_for's
    # cwd-overlap tier (the strongest signal, ahead of recency). Worktrees
    # nest under @cwd (the registered project path), matching how a real
    # project code worktree (<repo>/.claude/worktrees/{id}--{slug}) always
    # nests under its own repo root, so the statusline's own SLUG match
    # still resolves to this project's store (not the global one).
    add_active_intent(id: "79", slug: "a", title: "Alpha work")
    add_active_intent(id: "80", slug: "b", title: "Beta work")
    wt_a = File.join(@cwd, ".claude", "worktrees", "79--a")
    wt_b = File.join(@cwd, ".claude", "worktrees", "80--b")
    FileUtils.mkdir_p(wt_a)
    FileUtils.mkdir_p(wt_b)

    register_per_intent_session(session: "sess-C", id: "79", cwd: wt_a, now: Time.now - 100)
    register_per_intent_session(session: "sess-C", id: "80", cwd: wt_b, now: Time.now)

    out_a = render(stdin_json(session_id: "sess-C", cwd: wt_a))
    assert_includes out_a, "79"
    assert_includes out_a, "Alpha work"
    refute_includes out_a, "Beta work"

    out_b = render(stdin_json(session_id: "sess-C", cwd: wt_b))
    assert_includes out_b, "80"
    assert_includes out_b, "Beta work"
    refute_includes out_b, "Alpha work"
  end

  def test_falls_back_to_newest_row_without_a_cwd_signal
    # No candidate row's cwd overlaps the query cwd: the most-recently-seen
    # row wins (Sessions.active_for's recency tiebreak). The query cwd still
    # nests under @cwd (the registered project path) so the statusline's
    # SLUG match resolves to this project's store, same reasoning as above.
    add_active_intent(id: "79", slug: "a", title: "Older work")
    add_active_intent(id: "80", slug: "b", title: "Newer work")

    register_per_intent_session(session: "sess-D", id: "79",
                                cwd: File.join(@cwd, "wt79"), now: Time.now - 100)
    register_per_intent_session(session: "sess-D", id: "80",
                                cwd: File.join(@cwd, "wt80"), now: Time.now)

    out = render(stdin_json(session_id: "sess-D", cwd: File.join(@cwd, "somewhere", "unrelated")))
    assert_includes out, "80"
    assert_includes out, "Newer work"
    refute_includes out, "Older work"
  end

  def test_no_jq_invoked_and_ruby_used_only_via_the_plastic_db_cli
    # The old constraint (intent 59) was "no ruby or jq invoked" (pure
    # bash/grep/sed). Intent 41 ACTION_12 deliberately trades that for ONE
    # bounded ruby call into plastic-db (fail-soft, tolerated absence) so the
    # statusline can read the DB-authoritative session state; jq is still
    # never used.
    body = File.read(STATUSLINE)
    code = body.each_line.reject { |l| l.strip.start_with?("#") }.join
    refute_match(/\bjq\b/, code, "statusline must never invoke jq")

    ruby_lines = code.each_line.select { |l| l =~ /\bruby\b/ }
    assert_equal 1, ruby_lines.size,
                "expected exactly one ruby invocation (the plastic-db bridge cutover)"
    assert_match(/\bruby\b.*\bbridge\b/, ruby_lines.first,
                "the one ruby call must be the plastic-db bridge verb")
  end
end
