# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "json"
require_relative "../scripts/dashboard"

# Tests for scripts/dashboard.rb — the deterministic work cockpit.
#
# Strategy:
#   * Build a small, fully-controlled fixture store in a tmpdir (deterministic content).
#   * Run the engine as a subprocess with PLASTIC_HOME + DASHBOARD_TODAY pinned.
#   * Assert classification via --json and golden-snapshot the rendered text.
#
# The golden snapshots under test/fixtures/dashboard/ ARE the skill's eval: if output
# drifts without an intentional template change, these fail. Regenerate intentionally
# with REGENERATE_GOLDEN=1.
class DashboardTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/dashboard.rb", __dir__)
  GOLDEN = File.expand_path("fixtures/dashboard", __dir__)
  TODAY = "2026-06-12"

  def setup
    @home = Dir.mktmpdir("plastic-dash")
    build_fixture(@home)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
  end

  # --- helpers ---------------------------------------------------------------

  def run_dash(*args)
    env = { "PLASTIC_HOME" => @home, "DASHBOARD_TODAY" => TODAY }
    out = IO.popen(env, ["ruby", SCRIPT, *args], &:read)
    [out, $?.exitstatus]
  end

  def write_intent(store, id, slug, frontmatter, body: "", files: {})
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    fm = frontmatter.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.join(', ')}]" : v}" }.join("\n")
    File.write(File.join(dir, "#{id}--#{slug}.md"), "---\n#{fm}\n---\n\n## Intent\n#{frontmatter[:intent]}\n#{body}\n")
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  # A compact store exercising every quadrant, the research band, and each flag.
  def build_fixture(home)
    FileUtils.mkdir_p(File.join(home, "store"))
    demo = File.join(home, "projects", "demo", "store")
    FileUtils.mkdir_p(demo)

    File.write(File.join(home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo\"\n    status: active\n")

    # Global store: one completed intent (recency source).
    write_intent(File.join(home, "store"), "1", "global-done",
                 { id: 1, intent: "Global completed thing", author: "human", tags: %w[plastic], created: "2026-05-01" },
                 files: { "outcome.md" => "done" })
    File.write(File.join(home, "INDEX.md"), <<~IDX)
      # Index
      ## Active
      ## Future
      ## Clusters
      ## Abandoned
      ## Completed
      - [1 — Global completed thing](store/1--global-done/1--global-done.md) — 2026-05-01
    IDX

    # Demo project intents.
    # NEXT BIG THING: human root, chain non-empty, implementation, no plan -> high+big -> drive
    write_intent(demo, "1", "big-idea",
                 { id: 1, intent: "Big strategic idea", author: "human", tags: %w[demo], chain: %w[1a], created: "2026-06-10" })
    # QUICK WIN: explicit value:high + has plan -> high+small -> defer (dispatchable knock-off)
    write_intent(demo, "2", "quick-win",
                 { id: 2, intent: "Quick high-value win", author: "human", tags: %w[demo], value: "high", created: "2026-06-10" },
                 files: { "plan.md" => "p", "checklist.md" => "- [ ] x\n" })
    # DEFER: bugfix -> low+small -> defer
    write_intent(demo, "3", "small-bug",
                 { id: 3, intent: "Small bug to squash", author: "agent", tags: %w[demo bugfix], created: "2026-06-10" })
    # TRIAGE: agent root, no chain, implementation -> low+big -> triage
    write_intent(demo, "4", "questionable",
                 { id: 4, intent: "Questionable big thing", author: "agent", tags: %w[demo], created: "2026-06-10" })
    # RESEARCH band: research type
    write_intent(demo, "5", "research-it",
                 { id: 5, intent: "Research a thing", author: "human", tags: %w[demo research], created: "2026-06-10" })
    # ACTIVE + in-progress: partial checklist, ledger stamp within 24h of TODAY.
    write_intent(demo, "6", "in-flight",
                 { id: 6, intent: "Work in flight", author: "human", tags: %w[demo], created: "2026-06-10" },
                 files: { "spec.md" => "s", "plan.md" => "p", "checklist.md" => "- [x] done\n- [ ] todo\n",
                          "savepoint.md" => "2026-06-12T08:00:00Z  How  plan.md created\n" })
    # STALE + UNBLOCKED: old future, source is the completed global... use demo source 3? completed needed.
    # Make a completed demo intent and a future intent sourced from it (unblocked).
    write_intent(demo, "7", "done-dep",
                 { id: 7, intent: "Completed dependency", author: "human", tags: %w[demo], created: "2026-05-01" },
                 files: { "outcome.md" => "done", "savepoint.md" => "2026-06-11T09:00:00Z  Exec  outcome.md created\n" })
    write_intent(demo, "8", "stale-unblocked",
                 { id: 8, intent: "Stale unblocked follow-up", author: "agent", tags: %w[demo bugfix], sources: %w[7], created: "2026-05-01" })
    # NOT unblocked: future with two sources, only one done (7 done, 99 absent/undone).
    write_intent(demo, "9", "partly-blocked",
                 { id: 9, intent: "Partly blocked follow-up", author: "agent", tags: %w[demo bugfix], sources: %w[7 99], created: "2026-05-01" })

    # SPAWNED vs RELATIONAL chain (intent 68). Both are agent-authored BRANCH ids so the
    # human-root rule does not apply; the only difference is whether the chain entry is
    # reciprocated by a sources edge (spawned) or purely relational.
    # 4a SPAWNED: 4a1 lists 4a in its sources, so 4a "has spawned follow-on work" -> high.
    write_intent(demo, "4a", "spawned-parent",
                 { id: "4a", intent: "Spawned-from parent", author: "agent", tags: %w[demo], chain: %w[4a1], created: "2026-06-10" })
    write_intent(demo, "4a1", "spawned-child",
                 { id: "4a1", intent: "Child created from 4a", author: "agent", tags: %w[demo], sources: %w[4a], created: "2026-06-10" })
    # 4b RELATIONAL: chain entry to 9, but NO intent lists 4b in its sources -> NOT high.
    write_intent(demo, "4b", "relational-only",
                 { id: "4b", intent: "Relational not-spawned chain", author: "agent", tags: %w[demo], chain: %w[9], created: "2026-06-10" })

    # Task 9 fixtures (intent 125) -------------------------------------------

    # Birth-only savepoint: only the creation stamp ("What  created"), no other file and
    # no partial checklist -> must NOT be flagged "in-progress" (D3).
    write_intent(demo, "10", "birth-only",
                 { id: 10, intent: "Born but untouched", author: "agent", tags: %w[demo], created: "2026-06-05" },
                 files: { "savepoint.md" => "2026-06-05T09:00:00Z  What  created\n" })

    # Trivially unblocked at birth: its one source (7) completed BEFORE this intent was
    # even created, so "all sources done" is the birth default, not a genuine wait ->
    # must NOT be flagged "unblocked" (D4).
    write_intent(demo, "11", "trivially-unblocked",
                 { id: 11, intent: "Trivially unblocked at birth", author: "agent", tags: %w[demo], sources: %w[7], created: "2026-06-01" })

    # Over-long intent text: exercises the 120-char truncation + ellipsis on `.line`.
    write_intent(demo, "12", "long-text",
                 { id: 12, intent: "A" * 150, author: "agent", tags: %w[demo], created: "2026-06-04" })

    # Six extra bugfix (low+small -> defer) intents: pushes the project's future pool
    # (already holding 3/4/8/9 and friends) past NEXT_WORK_CAP so next_work must cap
    # it with "+N more".
    (1..6).each do |i|
      write_intent(demo, "d#{i}", "bugfix-filler-#{i}",
                   { id: "d#{i}", intent: "Bugfix filler #{i}", author: "agent", tags: %w[demo bugfix], created: "2026-06-0#{i}" })
    end

    File.write(File.join(home, "projects", "demo", "INDEX.md"), <<~IDX)
      # Index
      ## Active
      - [6 — Work in flight](store/6--in-flight/6--in-flight.md)
      ## Future
      - [1 — Big strategic idea](store/1--big-idea/1--big-idea.md)
      - [2 — Quick high-value win](store/2--quick-win/2--quick-win.md)
      - [3 — Small bug to squash](store/3--small-bug/3--small-bug.md)
      - [4 — Questionable big thing](store/4--questionable/4--questionable.md)
      - [5 — Research a thing](store/5--research-it/5--research-it.md)
      - [8 — Stale unblocked follow-up](store/8--stale-unblocked/8--stale-unblocked.md)
      - [9 — Partly blocked follow-up](store/9--partly-blocked/9--partly-blocked.md)
      - [4a — Spawned-from parent](store/4a--spawned-parent/4a--spawned-parent.md)
      - [4a1 — Child created from 4a](store/4a1--spawned-child/4a1--spawned-child.md)
      - [4b — Relational not-spawned chain](store/4b--relational-only/4b--relational-only.md)
      - [10 — Born but untouched](store/10--birth-only/10--birth-only.md)
      - [11 — Trivially unblocked at birth](store/11--trivially-unblocked/11--trivially-unblocked.md)
      - [12 — A very long intent line](store/12--long-text/12--long-text.md)
      - [d1 — Bugfix filler 1](store/d1--bugfix-filler-1/d1--bugfix-filler-1.md)
      - [d2 — Bugfix filler 2](store/d2--bugfix-filler-2/d2--bugfix-filler-2.md)
      - [d3 — Bugfix filler 3](store/d3--bugfix-filler-3/d3--bugfix-filler-3.md)
      - [d4 — Bugfix filler 4](store/d4--bugfix-filler-4/d4--bugfix-filler-4.md)
      - [d5 — Bugfix filler 5](store/d5--bugfix-filler-5/d5--bugfix-filler-5.md)
      - [d6 — Bugfix filler 6](store/d6--bugfix-filler-6/d6--bugfix-filler-6.md)
      ## Clusters
      ## Abandoned
      ## Completed
      - [7 — Completed dependency](store/7--done-dep/7--done-dep.md) — 2026-05-02
    IDX
  end

  def assert_golden(name, actual)
    path = File.join(GOLDEN, name)
    if ENV["REGENERATE_GOLDEN"]
      FileUtils.mkdir_p(GOLDEN)
      File.write(path, actual)
      skip "regenerated #{name}"
    end
    expected = File.read(path)
    assert_equal expected, actual, "#{name} drifted from golden (REGENERATE_GOLDEN=1 to update)"
  end

  # --- classification (via --json) ------------------------------------------

  def test_classification_quadrants_and_dispositions
    out, status = run_dash("project", "demo", "--json")
    assert_equal 0, status
    data = JSON.parse(out)

    # Next big thing is the high+big human root idea.
    assert_equal "1", data["next_big_thing"]

    by_id = {}
    data["dispatchable_queue"].each { |r| by_id[r["id"]] = r }

    # Bugfix -> defer, small.
    assert_equal "defer", by_id["3"]["disposition"]
    assert_equal "small", by_id["3"]["effort"]
    # Research -> research band, dispatchable.
    assert_equal "research", by_id["5"]["disposition"]
    # Quick win (explicit value:high + plan) is dispatchable defer, high value.
    assert_equal "high", by_id["2"]["value"]
    # Stale + unblocked flags present.
    assert_includes by_id["8"]["flags"], "stale"
    assert_includes by_id["8"]["flags"], "unblocked"

    # human_only holds drive + triage (the big idea + the questionable big thing).
    assert_includes data["human_only"], "1"
    assert_includes data["human_only"], "4"
    refute_includes data["human_only"], "3"
  end

  def test_dispatchable_queue_is_rank_ordered
    out, = run_dash("project", "demo", "--json")
    ranks = JSON.parse(out)["dispatchable_queue"].map { |r| r["rank"] }
    assert_equal ranks.sort, ranks
    assert_equal (1..ranks.size).to_a, ranks
  end

  # --- markdown-board data payload (intent 37) -------------------------------

  def test_data_global_shape
    out, status = run_dash("continue", "--data")
    assert_equal 0, status
    data = JSON.parse(out)
    assert_equal "global", data["mode"]
    %w[date summary next_work next_total next_shown counts projects project_totals footer].each do |k|
      assert data.key?(k), "missing #{k}"
    end
    refute data.key?("recently_worked"), "recently_worked is replaced by the prose summary (D6)"
    # Global next_work is global-store intents only (no project intents folded in).
    scopes = data["next_work"].map { |r| r["scope"] }.reject(&:empty?)
    assert(scopes.all? { |s| s == "global" }, "global next_work leaked non-global scope: #{scopes.uniq}")
  end

  def test_data_project_shape
    out, status = run_dash("project", "demo", "--data")
    assert_equal 0, status
    data = JSON.parse(out)
    assert_equal "project", data["mode"]
    assert_equal "demo", data["slug"]
    %w[summary next_work counts active active_total active_shown next_total next_shown footer].each do |k|
      assert data.key?(k), "missing #{k}"
    end
    refute data.key?("future"), "the raw future list must be gone (D1: duplicates next_work)"
    refute data.key?("recently_worked"), "recently_worked is replaced by the prose summary (D1)"
  end

  def test_last_accessed_prefers_ledger_over_created
    dir = Dir.mktmpdir("plastic-dash-lastaccessed")
    File.write(File.join(dir, "savepoint.md"), "2026-06-12T08:00:00Z  How  plan.md created\n")
    assert_equal "2026-06-12T08:00:00Z", last_accessed_at(dir, "2026-01-01")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  def test_value_high_for_human_root
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    entry = data["next_work"].find { |r| r["id"] == "1" }
    refute_nil entry, "expected id 1 in next_work"
    assert_equal "high", entry["value"] # human-authored root (high value)
  end

  # intent 68: a SPAWNED chain (reciprocal sources edge) is high; a purely RELATIONAL
  # chain (no reciprocal sources) is NOT high on the chain signal alone.
  # --all: this test asserts on value_of's classification via next_work, not on caps;
  # id 4b (low value) ranks outside the new default next_work cap of 5 (intent 202,
  # D5), so --all is needed to keep this a test of classification, not of the cap.
  def test_spawned_chain_is_high_relational_chain_is_not
    out, = run_dash("project", "demo", "--data", "--all")
    data = JSON.parse(out)
    by_id = data["next_work"].each_with_object({}) { |r, h| h[r["id"]] = r }
    assert_equal "high", by_id["4a"] && by_id["4a"]["value"], "spawned intent (4a1 lists it in sources) must be high"
    assert_equal "low", by_id["4b"] && by_id["4b"]["value"], "purely relational chain must NOT be high"
  end

  def test_unblocked_requires_all_sources_done
    out, = run_dash("project", "demo", "--json")
    by_id = {}
    JSON.parse(out)["dispatchable_queue"].each { |r| by_id[r["id"]] = r }
    assert_includes by_id["8"]["flags"], "unblocked"      # all sources done
    refute_includes (by_id["9"]&.dig("flags") || []), "unblocked" # one source still open
  end

  # --- Task 9: birth-only savepoint / trivial-unblock / caps / truncation ---

  def test_birth_only_savepoint_is_not_in_progress
    out, = run_dash("project", "demo", "--json")
    by_id = {}
    JSON.parse(out)["dispatchable_queue"].each { |r| by_id[r["id"]] = r }
    refute_includes (by_id["10"]&.dig("flags") || []), "in-progress"
  end

  def test_source_completed_before_created_is_not_unblocked
    out, = run_dash("project", "demo", "--json")
    by_id = {}
    JSON.parse(out)["dispatchable_queue"].each { |r| by_id[r["id"]] = r }
    refute_includes (by_id["11"]&.dig("flags") || []), "unblocked"
    # Confirm the pre-existing genuine-wait cases still behave (id 8: genuine wait
    # present; id 9: sources incomplete).
    assert_includes by_id["8"]["flags"], "unblocked"
    refute_includes (by_id["9"]&.dig("flags") || []), "unblocked"
  end

  def test_next_work_capped_at_five_by_default_with_honest_total
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    # The project's future pool (19 records: 1,2,3,4,5,8,9,4a,4a1,4b,10,11,12,d1..d6) is over
    # the new NEXT_WORK_CAP (5): capped to 5 real entries, no "+N more" marker; the total
    # rides on the payload instead (D5).
    assert_equal 5, data["next_work"].size
    refute(data["next_work"].any? { |r| r["id"].to_s.empty? }, "no blank marker row expected")
    assert_equal 19, data["next_total"]
    assert_equal 5, data["next_shown"]
  end

  def test_next_work_all_flag_returns_every_row_uncapped
    out, = run_dash("project", "demo", "--data", "--all")
    data = JSON.parse(out)
    assert_equal 19, data["next_work"].size
    assert_equal 19, data["next_total"]
    assert_equal 19, data["next_shown"]
    refute(data["next_work"].any? { |r| r["id"].to_s.empty? })
  end

  def test_next_work_limit_next_flag_overrides_default_cap
    out, = run_dash("project", "demo", "--data", "--limit-next", "2")
    data = JSON.parse(out)
    assert_equal 2, data["next_work"].size
    assert_equal 2, data["next_shown"]
    assert_equal 19, data["next_total"]
  end

  # Truncation is a property of next_work's line-building for any over-120-char
  # intent text; asserted directly (in-process, hermetic) rather than by locating a
  # long-text fixture id within the capped, rank-ordered "demo" project pool, since
  # id 12 (the fixture's over-120-char intent) ranks low value/big effort/no flags
  # and falls outside NEXT_WORK_CAP for that shared fixture (over-cap coverage lives
  # in test_next_work_over_cap_is_capped_with_more_marker above).
  def test_intent_line_truncated_over_120_chars
    rec = { id: "99", intent: "A" * 150, scope: "project:demo", lifecycle: "what",
            value: :low, effort: :big, disposition: "triage", flags: [] }
    entry = next_work([rec]).first
    assert entry[:line].start_with?("99 "), "unexpected line shape: #{entry[:line]}"
    text = entry[:line].delete_prefix("99 ")
    assert text.end_with?("…"), "expected ellipsis truncation: #{text}"
    assert_operator text.length, :<=, 121
  end

  def test_next_work_shape
    out, = run_dash("project", "demo", "--data")
    list = JSON.parse(out)["next_work"]
    refute_empty list
    list.each do |r|
      %w[id intent scope lifecycle value disposition flags what flags_label line].each do |k|
        assert r.key?(k), "next_work entry missing #{k}: #{r.inspect}"
      end
      refute_includes r["line"], "<br>"
    end
    real = list.reject { |r| r["id"].to_s.empty? }
    refute_empty real
    real.each { |r| assert r["line"].start_with?("#{r['id']} "), "line not id-led: #{r["line"]}" }
  end

  def test_active_carries_cell_fields
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    active = data["active"].reject { |r| r["id"].to_s.empty? }
    refute_empty active
    active.each { |r| %w[what stage worker activity].each { |k| assert r.key?(k), "active missing #{k}: #{r.inspect}" } }
    assert_operator data["active"].size, :<=, 3
    assert_equal [data["active_shown"], data["active_total"]].min, data["active_shown"]
  end

  def with_lock_visibility_fixture
    saved_home = @home
    @home = Dir.mktmpdir("plastic-dash-lock-visibility")
    demo = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(demo)
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo-locks\"\n    status: active\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n")

    fixtures = {
      "c" => ["claude-owner", "Claude enriched"],
      "x" => ["codex-owner", "Codex enriched"],
      "l" => ["legacy", "Legacy lock"],
      "s" => ["stale", "Stale lock"],
      "b" => ["broken", "Corrupt lock"],
      "n" => ["none", "No lock"],
    }
    fixtures.each do |id, (slug, title)|
      write_intent(demo, id, slug,
                   { id: id, intent: title, author: "agent", tags: %w[demo], created: "2026-06-01" })
    end

    # Give three lock-state rows distinct lifecycle depths so this same fixture
    # proves worker projection never disturbs finish-first ordering.
    File.write(File.join(demo, "c--claude-owner", "spec.md"), "s")
    File.write(File.join(demo, "c--claude-owner", "plan.md"), "p")
    File.write(File.join(demo, "c--claude-owner", "checklist.md"), "- [ ] x\n")
    File.write(File.join(demo, "x--codex-owner", "spec.md"), "s")
    File.write(File.join(demo, "x--codex-owner", "plan.md"), "p")
    File.write(File.join(demo, "l--legacy", "spec.md"), "s")
    write_intent(demo, "f", "future-work",
                 { id: "f", intent: "Future work", author: "agent", tags: %w[demo bugfix], created: "2026-06-01" })

    now = Time.now
    claude_dir = File.join(demo, "c--claude-owner")
    Lock.acquire(claude_dir, session: "claude-session", harness: "claude",
                 agent: "plastic-enforcer", now: now)
    Claim.acquire_claim(claude_dir, "spec.md", session: "claude-session",
                        delegate: "writer-session", now: now)
    Lock.acquire(File.join(demo, "x--codex-owner"), session: "codex-session",
                 harness: "codex", agent: "plastic-planner", now: now)
    legacy_dir = File.join(demo, "l--legacy")
    File.write(File.join(legacy_dir, "delivery.lock"), JSON.generate(
      "type" => "delivery", "owner_session" => "legacy-session", "host" => "test",
      "acquired_at" => now.utc.iso8601, "delegates" => []
    ))
    stale_dir = File.join(demo, "s--stale")
    Lock.acquire(stale_dir, session: "stale-session", harness: "codex",
                 agent: "plastic-executor", now: now - Lock::TTL_SECONDS - 60)
    File.utime(now - Lock::TTL_SECONDS - 60, now - Lock::TTL_SECONDS - 60,
               File.join(stale_dir, "delivery.lock"))
    File.write(File.join(demo, "b--broken", "delivery.lock"), "not json")

    active_lines = fixtures.map do |id, (slug, title)|
      "- [#{id} - #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md)"
    end
    File.write(File.join(@home, "projects", "demo", "INDEX.md"),
               "# Index\n## Active\n#{active_lines.join("\n")}\n## Future\n" \
               "- [f - Future work](store/f--future-work/f--future-work.md)\n" \
               "## Clusters\n## Abandoned\n## Completed\n")
    yield
  ensure
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
    @home = saved_home
  end

  def test_project_active_rows_show_worker_and_durable_activity_states
    with_lock_visibility_fixture do
      out, status = run_dash("project", "demo", "--data", "--all")
      assert_equal 0, status
      rows = JSON.parse(out)["active"].to_h { |row| [row["id"], row] }
      assert_equal "plastic-enforcer · Claude", rows["c"]["worker"]
      assert_equal "Fresh · writer writer-session", rows["c"]["activity"]
      assert_equal "plastic-planner · Codex", rows["x"]["worker"]
      assert_equal "Fresh", rows["x"]["activity"]
      assert_equal "Unknown · Unknown", rows["l"]["worker"]
      assert_equal "Fresh", rows["l"]["activity"]
      assert_equal "plastic-executor · Codex", rows["s"]["worker"]
      assert_equal "Stale", rows["s"]["activity"]
      assert_equal "Unknown · Unknown", rows["b"]["worker"]
      assert_equal "Corrupt", rows["b"]["activity"]
      assert_equal "Unknown · Unknown", rows["n"]["worker"]
      assert_equal "No lock", rows["n"]["activity"]
    end
  end

  def test_plain_project_includes_worker_and_activity_without_changing_caps
    with_lock_visibility_fixture do
      out, status = run_dash("project", "demo", "--plain")
      assert_equal 0, status
      assert_includes out, "plastic-enforcer · Claude · Fresh · writer writer-session"
      assert_includes out, "Unknown · Unknown · No lock"
      assert_equal 6, out.lines.count { |line| line.start_with?(STATUS_GLYPH["active"]) }
    end
  end

  def test_lock_visibility_preserves_default_cap_finish_first_totals_and_next_work
    with_lock_visibility_fixture do
      out, status = run_dash("project", "demo", "--data")
      assert_equal 0, status
      data = JSON.parse(out)
      assert_equal %w[c x l], data["active"].map { |row| row["id"] }
      assert_equal 3, data["active_shown"]
      assert_equal 6, data["active_total"]
      assert_equal ["f"], data["next_work"].map { |row| row["id"] }
      assert_equal 1, data["next_shown"]
      assert_equal 1, data["next_total"]
      refute data["next_work"].first.key?("worker")
      refute data["next_work"].first.key?("activity")
    end
  end

  def test_lock_visibility_preserves_limit_active_and_all_paging
    with_lock_visibility_fixture do
      limited, = run_dash("project", "demo", "--data", "--limit-active", "2")
      limited_data = JSON.parse(limited)
      assert_equal %w[c x], limited_data["active"].map { |row| row["id"] }
      assert_equal 2, limited_data["active_shown"]
      assert_equal 6, limited_data["active_total"]

      all, = run_dash("project", "demo", "--data", "--all")
      all_data = JSON.parse(all)
      assert_equal %w[c x l b n s], all_data["active"].map { |row| row["id"] }
      assert_equal 6, all_data["active_shown"]
      assert_equal 6, all_data["active_total"]
    end
  end

  def test_worker_fields_do_not_leak_to_global_data_or_auto_json
    with_lock_visibility_fixture do
      global, = run_dash("continue", "--data")
      auto, = run_dash("project", "demo", "--json")
      [JSON.parse(global), JSON.parse(auto)].each do |payload|
        serialized = JSON.generate(payload)
        refute_includes serialized, '"worker"'
        refute_includes serialized, '"activity"'
        refute_includes serialized, '"intent_dir"'
      end
    end
  end

  def test_internal_intent_dir_never_leaks_from_project_surfaces
    with_lock_visibility_fixture do
      data, = run_dash("project", "demo", "--data", "--all")
      plain, = run_dash("project", "demo", "--plain")
      terminal, = run_dash("project", "demo")
      [data, plain, terminal].each do |surface|
        refute_includes surface, "intent_dir"
        refute_includes surface, @home
      end
    end
  end

  def test_project_markdown_mechanical_fill_renders_five_active_columns_and_values
    with_lock_visibility_fixture do
      out, = run_dash("project", "demo", "--data")
      data = JSON.parse(out)
      template = File.read(File.expand_path("../skills/dashboard/templates/dashboard-project.md", __dir__))
      rows = data["active"].map do |row|
        "| #{row['id']} | #{row['what']} | #{row['stage']} | #{row['worker']} | #{row['activity']} |"
      end.join("\n")
      markdown = template.gsub("{{slug}}", data["slug"])
                         .gsub("{{date}}", data["date"])
                         .gsub("{{summary}}", data["summary"])
                         .gsub("{{active.rows}}", rows)
      assert_includes markdown, "| Id | What | Stage | Worker | Activity |"
      assert_includes markdown, "| c | Claude enriched | Exec | plastic-enforcer · Claude | Fresh · writer writer-session |"
      assert_includes markdown, "| x | Codex enriched | How | plastic-planner · Codex | Fresh |"
      markdown.lines.grep(/^\| [cxl] \|/).each do |line|
        assert_equal 6, line.count("|"), "expected exactly five Markdown cells: #{line.inspect}"
      end
    end
  end

  def test_project_render_uses_one_fixed_clock_at_the_ttl_boundary
    fixed_now = Time.utc(2026, 7, 14, 12, 0, 0)
    Dir.mktmpdir("plastic-dash-lock-clock") do |root|
      records = %w[a b].map do |id|
        dir = File.join(root, id)
        FileUtils.mkdir_p(dir)
        Lock.acquire(dir, session: "session-#{id}", harness: "codex",
                     agent: "plastic-enforcer", now: fixed_now)
        boundary = fixed_now - Lock::TTL_SECONDS
        File.utime(boundary, boundary, File.join(dir, "delivery.lock"))
        { id: id, intent: "Boundary #{id}", created: "2026-07-14", scope: "project:clock",
          status: "active", lifecycle: "exec", last_accessed_at: "", intent_dir: dir }
      end

      payload = render_data_project(records, "clock", all: true, now: fixed_now)
      assert_equal %w[Fresh Fresh], payload[:active].map { |row| row[:activity] }
    end
  end

  def test_plain_worker_values_normalize_hostile_lock_metadata
    with_lock_visibility_fixture do
      dir = File.join(@home, "projects", "demo", "store", "c--claude-owner")
      lock = Lock.read(dir)
      lock["owner_agent"] = "\e[31mbad\e[0m\nline\t| " + ("A" * 200)
      Lock.write(dir, lock)
      claim_path = Claim.path(dir, "spec.md")
      claim = JSON.parse(File.read(claim_path))
      claim["delegate"] = "\e[32mwriter\e[0m\r\n| " + ("W" * 200)
      File.write(claim_path, JSON.generate(claim))

      data_out, = run_dash("project", "demo", "--data", "--all")
      row = JSON.parse(data_out)["active"].find { |item| item["id"] == "c" }
      assert_operator row["worker"].length, :<=, INTENT_LINE_MAX_CHARS + 1
      assert_operator row["activity"].length, :<=, INTENT_LINE_MAX_CHARS + 1
      refute_match(/\e|[\r\n\t]/, row["worker"])
      refute_match(/\e|[\r\n\t]/, row["activity"])
      assert_includes row["worker"], "bad line \\|"
      assert_includes row["activity"], "writer \\|"

      plain, = run_dash("project", "demo", "--plain")
      active_line = plain.lines.find { |line| line.start_with?(STATUS_GLYPH["active"] + " c ") }
      refute_nil active_line
      refute_match(/\e|[\r\t]/, active_line)
      assert_equal 1, plain.lines.count { |line| line.include?("bad line \\|") }
      assert_includes active_line, "writer \\|"
    end
  end

  def test_project_markdown_template_has_worker_and_activity_columns
    template = File.read(File.expand_path("../skills/dashboard/templates/dashboard-project.md", __dir__))
    assert_includes template, "| Id | What | Stage | Worker | Activity |"
    assert_includes template, "| --- | --- | --- | --- | --- |"

    contract = File.read(File.expand_path("../skills/dashboard/SKILL.md", __dir__))
    assert_includes contract, "| {id} | {what} | {stage} | {worker} | {activity} |"
    assert_includes contract, "| _(none)_ | | | |"
  end

  def test_cell_escapes_pipe_in_intent
    rec = { id: "99", intent: "left | right\nmid", scope: "project:demo", lifecycle: "what",
            value: :low, effort: :big, disposition: "triage", flags: [] }
    entry = next_work([rec]).first
    assert_includes entry[:what], "\\|", "pipe must be escaped as \\|"
    refute_match(/(?<!\\)\|/, entry[:what], "no raw unescaped pipe in cell")
    refute_includes entry[:what], "\n", "newline must be collapsed"
  end

  def test_payload_has_no_future_list_key
    out, = run_dash("project", "demo", "--data")
    refute JSON.parse(out).key?("future")
  end

  # --- D2 "finish first" ordering + Active cap, isolated fixture -------------

  # A dedicated, throwaway store exercising D2's ordering rule: one active intent per
  # lifecycle stage (what/why/how/exec), plus a same-stage exec tie broken by savepoint
  # recency. Swaps @home so run_dash/write_intent work unchanged; restores it afterward so
  # the shared golden-tested fixture from setup is never touched by this.
  def with_finish_first_fixture
    saved_home = @home
    @home = Dir.mktmpdir("plastic-dash-finish-first")
    demo = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(demo)
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo-ff\"\n    status: active\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n")

    write_intent(demo, "w", "what-stage", { id: "w", intent: "What stage active", author: "agent", tags: %w[demo], created: "2026-06-01" })
    write_intent(demo, "y", "why-stage", { id: "y", intent: "Why stage active", author: "agent", tags: %w[demo], created: "2026-06-01" },
                 files: { "spec.md" => "s" })
    write_intent(demo, "h", "how-stage", { id: "h", intent: "How stage active", author: "agent", tags: %w[demo], created: "2026-06-01" },
                 files: { "spec.md" => "s", "plan.md" => "p" })
    write_intent(demo, "e1", "exec-earlier", { id: "e1", intent: "Exec earlier savepoint", author: "agent", tags: %w[demo], created: "2026-06-01" },
                 files: { "spec.md" => "s", "plan.md" => "p", "checklist.md" => "- [ ] x\n",
                          "savepoint.md" => "2026-06-10T00:00:00Z  How  plan.md created\n" })
    write_intent(demo, "e2", "exec-later", { id: "e2", intent: "Exec later savepoint", author: "agent", tags: %w[demo], created: "2026-06-01" },
                 files: { "spec.md" => "s", "plan.md" => "p", "checklist.md" => "- [ ] x\n",
                          "savepoint.md" => "2026-06-11T00:00:00Z  How  plan.md created\n" })

    File.write(File.join(@home, "projects", "demo", "INDEX.md"), <<~IDX)
      # Index
      ## Active
      - [w - What stage active](store/w--what-stage/w--what-stage.md)
      - [y - Why stage active](store/y--why-stage/y--why-stage.md)
      - [h - How stage active](store/h--how-stage/h--how-stage.md)
      - [e1 - Exec earlier savepoint](store/e1--exec-earlier/e1--exec-earlier.md)
      - [e2 - Exec later savepoint](store/e2--exec-later/e2--exec-later.md)
      ## Future
      ## Clusters
      ## Abandoned
      ## Completed
    IDX

    yield
  ensure
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
    @home = saved_home
  end

  def test_active_ordered_finish_first_across_stages_with_tie_break
    with_finish_first_fixture do
      out, status = run_dash("project", "demo", "--data", "--all")
      assert_equal 0, status
      ids = JSON.parse(out)["active"].map { |r| r["id"] }
      assert_equal %w[e2 e1 h y w], ids
    end
  end

  def test_active_capped_at_three_by_default_honest_total
    with_finish_first_fixture do
      out, = run_dash("project", "demo", "--data")
      data = JSON.parse(out)
      assert_equal %w[e2 e1 h], data["active"].map { |r| r["id"] }
      assert_equal 5, data["active_total"]
      assert_equal 3, data["active_shown"]
    end
  end

  def test_active_limit_active_flag_overrides_default_cap
    with_finish_first_fixture do
      out, = run_dash("project", "demo", "--data", "--limit-active", "1")
      data = JSON.parse(out)
      assert_equal %w[e2], data["active"].map { |r| r["id"] }
      assert_equal 5, data["active_total"]
      assert_equal 1, data["active_shown"]
    end
  end

  # --- prose summary: completed/completed_on, not the 24h recently_worked window ---

  def test_recent_delivery_summary_ignores_recency_uses_completed_on
    old = { id: "9", scope: "project:x", status: "completed", completed_on: "2020-01-01", intent: "Ancient delivery" }
    recent = { id: "10", scope: "project:x", status: "completed", completed_on: "2026-06-01", intent: "Recent delivery" }
    summary = recent_delivery_summary([old, recent], project_scope: "project:x")
    assert_includes summary, "10"
    assert_includes summary, "Recent delivery"
  end

  def test_recent_delivery_summary_empty_state_sentence
    summary = recent_delivery_summary([], project_scope: "project:x")
    assert_match(/no.*delivered|nothing.*delivered/i, summary)
  end

  # Integration: the shared fixture's demo project has exactly one completed intent, id 7
  # "Completed dependency", completed_on "2026-05-02" - 41 days before TODAY (2026-06-12),
  # well outside any 24h window. If the summary is still wrongly sourced from
  # recently_worked's 24h window, this intent would never appear and the test fails.
  def test_data_project_summary_not_windowed_to_24h
    out, = run_dash("project", "demo", "--data")
    summary = JSON.parse(out)["summary"]
    assert_includes summary, "7"
  end

  # Integration: "broken" is registered in projects.yml but has no store directory on disk
  # (same trick test_problem_store_surfaces_warn_or_fail_without_raising already uses), so
  # scoped records for it are empty - a real zero-completed-work scope.
  def test_data_project_summary_empty_state_when_scope_has_no_intents
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo\"\n    status: active\n" \
               "  broken:\n    path: \"/tmp/broken-missing\"\n    status: active\n")
    out, status = run_dash("project", "broken", "--data")
    assert_equal 0, status
    assert_match(/no.*delivered|nothing.*delivered/i, JSON.parse(out)["summary"])
  end

  def test_data_global_summary_present
    out, = run_dash("continue", "--data")
    summary = JSON.parse(out)["summary"]
    refute_empty summary
    assert_includes summary, "1" # the global store's one completed intent
  end

  # --- footer: honest totals (D5/AC8) ----------------------------------------

  def test_project_footer_states_true_totals
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    assert_includes data["footer"], "#{data['active_shown']} of #{data['active_total']}"
    assert_includes data["footer"], "#{data['next_shown']} of #{data['next_total']}"
  end

  def test_global_footer_states_true_totals
    out, = run_dash("continue", "--data")
    data = JSON.parse(out)
    assert_includes data["footer"], "#{data['next_shown']} of #{data['next_total']}"
  end

  # --- store health (doctor --store per board) -------------------------------

  def test_global_board_includes_store_health_scoped_global
    out, status = run_dash("continue", "--data")
    assert_equal 0, status
    data = JSON.parse(out)
    sh = data["store_health"]
    refute_nil sh, "global --data payload missing store_health"
    assert_equal "global", sh["scope"]
    assert_includes %w[pass warn fail], sh["status"]
    %w[pass warn fail total].each { |k| assert sh["summary"].key?(k), "summary missing #{k}" }
  end

  def test_project_board_includes_store_health_scoped_slug
    out, status = run_dash("project", "demo", "--data")
    assert_equal 0, status
    data = JSON.parse(out)
    sh = data["store_health"]
    refute_nil sh, "project --data payload missing store_health"
    assert_equal "demo", sh["scope"]
    assert_includes %w[pass warn fail], sh["status"]
    %w[pass warn fail total].each { |k| assert sh["summary"].key?(k), "summary missing #{k}" }
  end

  def test_json_payload_includes_store_health
    out, status = run_dash("project", "demo", "--json")
    assert_equal 0, status
    data = JSON.parse(out)
    sh = data["store_health"]
    refute_nil sh, "--json payload missing store_health"
    assert_equal "demo", sh["scope"]
  end

  # canonical_pretty_json exists because JSON.pretty_generate renders empty
  # containers as multi-line on some json gem versions ("[\n\n  ]") and
  # single-line on others ("[]"), which made the golden JSON test flake across
  # environments. Assert the helper always collapses to the single-line form.
  def test_canonical_pretty_json_collapses_empty_containers
    out = canonical_pretty_json({ "a" => [], "b" => {} })
    assert_includes out, "\"a\": []"
    assert_includes out, "\"b\": {}"
    refute_match(/\[\s*\n\s*\]/, out)
    refute_match(/\{\s*\n\s*\}/, out)
  end

  def test_problem_store_surfaces_warn_or_fail_without_raising
    # Register a project whose store directory does not exist on disk. The doctor
    # store check should surface this as warn/fail, and the dashboard must not crash.
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo\"\n    status: active\n" \
               "  broken:\n    path: \"/tmp/broken-missing\"\n    status: active\n")

    out, status = run_dash("project", "broken", "--data")
    assert_equal 0, status, "problem store must not change the dashboard exit code"
    data = JSON.parse(out)
    sh = data["store_health"]
    refute_nil sh
    assert_equal "broken", sh["scope"]
    assert_includes %w[warn fail], sh["status"], "missing project store should surface warn/fail"
  end

  # --- --plain mode (D4, fork 4) ----------------------------------------------

  def test_plain_project_prints_full_uncapped_plain_text
    out, status = run_dash("project", "demo", "--plain")
    assert_equal 0, status
    refute_match(/\|\s*---\s*\|/, out, "no Markdown table syntax expected")
    refute_match(/\+\d+ more/, out, "no truncation marker expected")
    # d6 is the last of 6 filler future intents; under the old cap (8) or the new default
    # cap (5) it would never show, so its presence proves --plain is genuinely uncapped.
    assert_includes out, "d6"
  end

  def test_plain_global_prints_full_uncapped_plain_text
    out, status = run_dash("continue", "--plain")
    assert_equal 0, status
    refute_match(/\|\s*---\s*\|/, out)
    refute_match(/\+\d+ more/, out)
  end

  def test_plain_project_missing_slug_returns_usage_error
    _out, status = run_dash("project", "--plain")
    assert_equal 2, status
  end

  # --- completion_dates: intent 202 gate-review bug -------------------------
  #
  # end-intent's --index-note flag (the documented completion path since it shipped)
  # writes the date FOLLOWED BY free-text note prose, not at the end of the line. The
  # old regex required the date to be the last thing on the line, so it silently missed
  # every noted entry. These pin the fix directly against completion_dates, hermetically,
  # without going through the dashboard subprocess.

  # The real em dash (U+2014), INDEX.md's normal on-write separator (scripts/end-intent's
  # own EM_DASH constant). Built from the codepoint via a Ruby unicode escape, exactly like
  # end-intent does, so this source line itself stays em-dash free.
  def em
    "\u2014"
  end

  def completion_dates_fixture(body)
    Dir.mktmpdir("plastic-dash-completion-dates") do |dir|
      path = File.join(dir, "INDEX.md")
      File.write(path, "# Index\n## Completed\n#{body}")
      yield path
    end
  end

  def test_completion_dates_parses_new_index_note_format
    completion_dates_fixture(
      "- [200 #{em} Doctor must verify hooks](store/200--doctor/200--doctor.md) #{em} " \
      "2026-07-14 auto, M tier. Long note prose follows right after the date.\n"
    ) do |path|
      dates = completion_dates(path)
      assert_equal "2026-07-14", dates["200"]
    end
  end

  def test_completion_dates_still_parses_old_end_of_line_format
    completion_dates_fixture(
      "- [7 #{em} Completed dependency](store/7--done-dep/7--done-dep.md) #{em} 2026-05-02\n"
    ) do |path|
      dates = completion_dates(path)
      assert_equal "2026-05-02", dates["7"]
    end
  end

  def test_completion_dates_ignores_second_date_in_note_prose
    completion_dates_fixture(
      "- [50 #{em} Some intent](store/50--x/50--x.md) #{em} 2026-07-10 note references " \
      "an earlier attempt on 2026-01-01 that failed.\n"
    ) do |path|
      dates = completion_dates(path)
      assert_equal "2026-07-10", dates["50"]
    end
  end

  def test_completion_dates_accepts_hyphen_and_em_dash_separators
    completion_dates_fixture(
      "- [60 #{em} Hyphen separated](store/60--x/60--x.md) - 2026-07-11 uses a plain hyphen.\n" \
      "- [61 #{em} Em dash separated](store/61--y/61--y.md) #{em} 2026-07-12 uses the real em dash.\n"
    ) do |path|
      dates = completion_dates(path)
      assert_equal "2026-07-11", dates["60"]
      assert_equal "2026-07-12", dates["61"]
    end
  end

  def test_completion_dates_warns_when_completed_section_entirely_undated
    completion_dates_fixture(
      "- [99 Bogus entry with no date anywhere on this line](store/99--bogus/99--bogus.md)\n"
    ) do |path|
      _out, err = capture_io { completion_dates(path) }
      assert_match(/completion_dates/, err)
      assert_match(%r{0/1}, err)
    end
  end

  # Board-level proof: the reported bug named a stale intent from weeks earlier as "most
  # recently delivered" because a new-format entry's date was silently invisible to the
  # summary. With the fix, a new-format completion dated TODAY correctly outranks an
  # old-format completion dated weeks earlier.
  def with_completion_summary_fixture
    saved_home = @home
    @home = Dir.mktmpdir("plastic-dash-completion-summary")
    demo = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(demo)
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo-completion-summary\"\n    status: active\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n")

    write_intent(demo, "30", "older-delivery",
                 { id: 30, intent: "Older delivery", author: "human", tags: %w[demo], created: "2026-05-01" },
                 files: { "outcome.md" => "done" })
    write_intent(demo, "31", "todays-delivery",
                 { id: 31, intent: "Todays delivery", author: "human", tags: %w[demo], created: TODAY },
                 files: { "outcome.md" => "done" })

    File.write(File.join(@home, "projects", "demo", "INDEX.md"),
      "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n" \
      "- [31 #{em} Todays delivery](store/31--todays-delivery/31--todays-delivery.md) #{em} " \
      "#{TODAY} auto, M tier. Delivered via end-intent --index-note today.\n" \
      "- [30 #{em} Older delivery](store/30--older-delivery/30--older-delivery.md) #{em} 2026-05-01\n")

    yield
  ensure
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
    @home = saved_home
  end

  def test_recent_delivery_summary_names_todays_new_format_delivery_not_older_one
    with_completion_summary_fixture do
      out, status = run_dash("project", "demo", "--data")
      assert_equal 0, status
      summary = JSON.parse(out)["summary"]
      assert_includes summary, "31 Todays delivery"
      assert_includes summary, TODAY
    end
  end

  # --- gate-review defect 1: summary must be short even when intent texts are huge --------
  #
  # Opus gate review on intent 202: the summary interpolated each intent's FULL `intent`
  # text (a paragraph on this store), making the "short by default" board's own summary the
  # longest thing on it. Fixed with a per-title word-boundary truncation plus a hard cap on
  # the fully assembled string (SUMMARY_CHAR_BUDGET, SUMMARY_TITLE_MAX_CHARS).

  def test_recent_delivery_summary_never_exceeds_char_budget_even_with_huge_intents
    huge = "Solve the deep architectural problem underlying this whole subsystem once and for all " * 30
    records = (1..5).map do |i|
      { id: i.to_s, scope: "project:x", status: "completed", completed_on: "2026-07-#{10 + i}",
        intent: "#{huge} (variant #{i})", done_at: nil }
    end
    summary = recent_delivery_summary(records, project_scope: "project:x")
    assert_operator summary.length, :<=, SUMMARY_CHAR_BUDGET
  end

  def test_recent_delivery_summary_truncates_titles_on_word_boundary_not_mid_word
    text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho"
    records = [{ id: "1", scope: "project:x", status: "completed", completed_on: "2026-07-14",
                 intent: text, done_at: nil }]
    summary = recent_delivery_summary(records, project_scope: "project:x")
    refute_includes summary, "omicron"
    assert_includes summary, "…"
  end

  def test_truncate_on_word_boundary_never_cuts_a_word_in_half
    text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa"
    truncated = truncate_on_word_boundary(text, 20)
    assert_operator truncated.length, :<=, 20
    body = truncated.sub(/…\z/, "")
    assert_equal text[0, body.length], body
    next_char = text[body.length]
    assert(next_char.nil? || next_char == " ", "expected a word boundary, got #{next_char.inspect}")
  end

  def test_truncate_on_word_boundary_returns_text_unchanged_when_it_fits
    assert_equal "short text", truncate_on_word_boundary("short text", 40)
  end

  # --- gate-review defect 2: same-day completion tie-break must be deterministic and true --
  #
  # Opus gate review on intent 202: completed_on only carries day granularity, 11+ intents
  # on this store share 2026-07-14, and Array#sort_by is not documented stable, so the
  # summary named 190/191/192 as "most recently delivered" even though 198, 199, 200, 201
  # and 203 completed the same day, later. Fixed with delivery_recency_key: completed_on,
  # then the savepoint's Done timestamp, then scope+id as a fully deterministic fallback.

  def test_done_timestamp_reads_the_done_line
    Dir.mktmpdir("plastic-dash-done-ts") do |dir|
      File.write(File.join(dir, "savepoint.md"),
        "2026-07-14T11:23:52Z  How  plan.md created\n" \
        "2026-07-14T11:49:10Z  Exec  outcome.md created\n" \
        "2026-07-14T13:17:23Z  Done  delivered\n")
      assert_equal "2026-07-14T13:17:23Z", done_timestamp(dir)
    end
  end

  def test_done_timestamp_nil_when_no_done_line
    Dir.mktmpdir("plastic-dash-done-ts") do |dir|
      File.write(File.join(dir, "savepoint.md"), "2026-07-14T11:23:52Z  How  plan.md created\n")
      assert_nil done_timestamp(dir)
    end
  end

  def test_done_timestamp_nil_when_no_savepoint_file
    Dir.mktmpdir("plastic-dash-done-ts") do |dir|
      assert_nil done_timestamp(dir)
    end
  end

  # The done_at values are deliberately NOT monotonic with id/array order: the lower id
  # (190) has the LATEST done_at, and it is listed FIRST in the input array too. A tie-break
  # that (wrongly) sorts only on completed_on, sees the two dates as equal, and lets
  # Array#sort_by's no-reordering-needed case fall through unchanged before .reverse would
  # name "203" here (array position 2, flipped to position 1) -- so this fixture cannot pass
  # by the same accident a naive "preserve input order" tie-break would produce.
  def test_recent_delivery_summary_same_day_tie_break_uses_later_done_timestamp
    truly_latest = { id: "190", scope: "project:x", status: "completed", completed_on: "2026-07-14",
                      done_at: "2026-07-14T20:00:00Z", intent: "Truly latest despite the lower id" }
    higher_id_earlier_done = { id: "203", scope: "project:x", status: "completed", completed_on: "2026-07-14",
                               done_at: "2026-07-14T08:00:00Z", intent: "Higher id but delivered earlier" }
    summary = recent_delivery_summary([truly_latest, higher_id_earlier_done], project_scope: "project:x", limit: 1)
    assert_includes summary, "190 Truly latest despite the lower id"
    refute_includes summary, "203"
  end

  # Full-store integration: three intents completed the SAME day per INDEX.md. done_at is
  # deliberately assigned so the truly-latest delivery (192) has neither the highest nor the
  # lowest id, and is listed in the MIDDLE of both the directory listing and the INDEX -- so
  # naming it first cannot be an accident of preserved array order or of reversing id order.
  def with_same_day_tie_fixture
    saved_home = @home
    @home = Dir.mktmpdir("plastic-dash-same-day-tie")
    demo = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(demo)
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "projects.yml"),
               "---\nprojects:\n  demo:\n    path: \"/tmp/demo-same-day-tie\"\n    status: active\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n")

    write_intent(demo, "190", "earliest-id",
                 { id: 190, intent: "Lowest id, middle done timestamp", author: "human", tags: %w[demo], created: "2026-07-10" },
                 files: { "outcome.md" => "done",
                          "savepoint.md" => "2026-07-14T08:00:00Z  Exec  started\n2026-07-14T12:00:00Z  Done  delivered\n" })
    write_intent(demo, "192", "middle-id",
                 { id: 192, intent: "Middle id, truly latest done timestamp", author: "human", tags: %w[demo], created: "2026-07-10" },
                 files: { "outcome.md" => "done",
                          "savepoint.md" => "2026-07-14T18:00:00Z  Exec  started\n2026-07-14T20:00:00Z  Done  delivered\n" })
    write_intent(demo, "203", "highest-id",
                 { id: 203, intent: "Highest id, earliest done timestamp", author: "human", tags: %w[demo], created: "2026-07-10" },
                 files: { "outcome.md" => "done",
                          "savepoint.md" => "2026-07-14T05:00:00Z  Exec  started\n2026-07-14T06:00:00Z  Done  delivered\n" })

    File.write(File.join(@home, "projects", "demo", "INDEX.md"),
      "# Index\n## Active\n## Future\n## Clusters\n## Abandoned\n## Completed\n" \
      "- [190 #{em} Lowest id, middle done timestamp](store/190--earliest-id/190--earliest-id.md) #{em} 2026-07-14\n" \
      "- [192 #{em} Middle id, truly latest done timestamp](store/192--middle-id/192--middle-id.md) #{em} 2026-07-14\n" \
      "- [203 #{em} Highest id, earliest done timestamp](store/203--highest-id/203--highest-id.md) #{em} 2026-07-14\n")

    yield
  ensure
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
    @home = saved_home
  end

  def test_same_day_completions_name_the_later_done_timestamp_first
    with_same_day_tie_fixture do
      out, status = run_dash("project", "demo", "--data")
      assert_equal 0, status
      summary = JSON.parse(out)["summary"]
      assert_includes summary, "192 Middle id, truly latest done timestamp"
      assert_includes summary, "190 Lowest id, middle done timestamp"
      assert_includes summary, "203 Highest id, earliest done timestamp"
      idx_192 = summary.index("192 Middle id")
      idx_190 = summary.index("190 Lowest id")
      idx_203 = summary.index("203 Highest id")
      assert_operator idx_192, :<, idx_190
      assert_operator idx_190, :<, idx_203
    end
  end

  def test_same_day_tie_break_is_deterministic_across_runs
    with_same_day_tie_fixture do
      a, = run_dash("project", "demo", "--data")
      b, = run_dash("project", "demo", "--data")
      assert_equal a, b
    end
  end

  # --- determinism -----------------------------------------------------------

  def test_render_is_deterministic
    a, = run_dash("continue")
    b, = run_dash("continue")
    assert_equal a, b
  end

  # --- golden snapshots (the skill eval) ------------------------------------

  def test_golden_continue
    out, status = run_dash("continue")
    assert_equal 0, status
    assert_golden "continue.txt", out
  end

  def test_golden_project
    out, status = run_dash("project", "demo")
    assert_equal 0, status
    assert_golden "project-demo.txt", out
  end

  def test_golden_json
    out, status = run_dash("all", "--json")
    assert_equal 0, status
    assert_golden "all.json", out
  end
end
