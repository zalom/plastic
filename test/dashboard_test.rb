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

    # Six extra bugfix (low+small -> defer) intents: pushes the defer quadrant (already
    # holding 3/4/8/9) past MATRIX_DATA_CAP so matrix_data must cap it with "+N more".
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
    %w[date recently_worked matrix counts projects project_totals].each { |k| assert data.key?(k), "missing #{k}" }
    # Global matrix is global-store intents only (no project intents folded in).
    scopes = data["matrix"].values.flatten.map { |r| r["scope"] }
    assert(scopes.all? { |s| s == "global" }, "global matrix leaked non-global scope: #{scopes.uniq}")
  end

  def test_data_project_shape
    out, status = run_dash("project", "demo", "--data")
    assert_equal 0, status
    data = JSON.parse(out)
    assert_equal "project", data["mode"]
    assert_equal "demo", data["slug"]
    %w[recently_worked matrix counts active future].each { |k| assert data.key?(k), "missing #{k}" }
  end

  def test_data_last_accessed_prefers_ledger_over_created
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    active = data["active"].find { |r| r["id"] == "6" }
    refute_nil active
    worked = data["recently_worked"].find { |r| r["id"] == "6" }
    assert_equal "2026-06-12T08:00:00Z", worked["last_accessed_at"]
  end

  def test_value_high_for_human_root
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    hi = (data["matrix"]["quick_win"] + data["matrix"]["next_big"]).map { |r| r["id"] }
    assert_includes hi, "1" # human-authored root (high value)
  end

  # intent 68: a SPAWNED chain (reciprocal sources edge) is high; a purely RELATIONAL
  # chain (no reciprocal sources) is NOT high on the chain signal alone.
  def test_spawned_chain_is_high_relational_chain_is_not
    out, = run_dash("project", "demo", "--data")
    data = JSON.parse(out)
    high_ids = (data["matrix"]["quick_win"] + data["matrix"]["next_big"]).map { |r| r["id"] }
    assert_includes high_ids, "4a", "spawned intent (4a1 lists it in sources) must be high"
    refute_includes high_ids, "4b", "purely relational chain must NOT be high"
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

  def test_matrix_quadrant_over_cap_is_capped_with_more_marker
    out, = run_dash("project", "demo", "--data")
    defer = JSON.parse(out)["matrix"]["defer"]
    # 3, 4a1, 4b, 8, 9 (bugfix or branch-id small effort, low value) + d1..d6 = 11
    # total, over MATRIX_DATA_CAP (8): capped to 8 real entries + one "+N more".
    assert_equal 9, defer.size
    more = defer.last
    assert_equal "", more["id"]
    assert_equal "→ +3 more", more["line"]
  end

  def test_intent_line_truncated_over_120_chars
    out, = run_dash("project", "demo", "--data")
    rec = JSON.parse(out)["matrix"]["triage"].find { |r| r["id"] == "12" }
    refute_nil rec, "expected id 12 in the triage quadrant"
    prefix = "⚑ 12 "
    assert rec["line"].start_with?(prefix), "unexpected line shape: #{rec["line"]}"
    text = rec["line"][prefix.length..-1]
    assert text.end_with?("…"), "expected ellipsis truncation: #{text}"
    assert_operator text.length, :<=, 121
  end

  def test_recently_worked_sorted_and_capped
    out, = run_dash("project", "demo", "--data")
    rows = JSON.parse(out)["recently_worked"]
    refute_empty rows
    keyed = rows.map { |r| r["status"] == "active" ? 0 : 1 }
    assert_equal keyed.sort, keyed, "active rows must precede done rows"
    assert_operator rows.size, :<=, 15
    rows.each { |r| assert r["line"].start_with?(r["glyph"]), "line not glyph-led: #{r["line"]}" }
  end

  def test_matrix_lists_are_glyph_led_with_bullets
    out, = run_dash("project", "demo", "--data")
    matrix = JSON.parse(out)["matrix"]
    bullets = { "quick_win" => "⚡", "next_big" => "★", "defer" => "→", "triage" => "⚑", "research" => "🔬" }
    matrix.each do |quad, list|
      list.each do |r|
        assert_equal bullets[quad], r["bullet"]
        assert r["line"].start_with?(bullets[quad]), "#{quad} line not glyph-led: #{r["line"]}"
        refute_includes r["line"], "<br>"
      end
    end
  end

  def test_future_sorted_created_desc
    out, = run_dash("project", "demo", "--data")
    created = JSON.parse(out)["future"].map { |r| r["created"] }
    assert_equal created.sort.reverse, created
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
