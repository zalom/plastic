# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "time"
require "date"
require "json"
require "open3"
require_relative "../scripts/dashboard"

# Tests for the dashboard SCREEN (intent 331d): scripts/dashboard.rb's
# screen_fields/render_screen, the new renderer over the SAME classified
# records `dashboard.rb`'s untouched pipeline already produces. Every test
# builds its own hermetic fixture store under a tmpdir and injects a fixed
# `now:` (ACTION_1 A5) - never the real ~/.plastic, never the ambient
# session id, never real wall-clock time for a freshness/date boundary.
#
# `load_all`/`stores` (scripts/dashboard.rb) read the top-level PLASTIC_HOME
# constant rather than taking a parameter, so this file re-derives the same
# store list from an explicit `home` through `stores_for`/`load_all_for`
# below - calling the SAME unedited `parse_intent`/`classify`/
# `index_section_ids`/`completion_dates`/`intent_dirs` dashboard.rb already
# ships, never a second copy of that logic.
class DashboardScreenTest < Minitest::Test
  NOW = Time.utc(2026, 9, 5, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir("plastic-dash-screen")
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "INDEX.md"), blank_index)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
  end

  # --- store re-derivation (no PLASTIC_HOME dependency) -----------------------

  def stores_for(home)
    list = []
    global = File.join(home, "store")
    list << { scope: "global", store: global, index: File.join(home, "INDEX.md") } if File.directory?(global)
    projects_root = File.join(home, "projects")
    if File.directory?(projects_root)
      Dir.children(projects_root).sort.each do |proj|
        store = File.join(projects_root, proj, "store")
        next unless File.directory?(store)
        list << { scope: "project:#{proj}", store: store, index: File.join(projects_root, proj, "INDEX.md") }
      end
    end
    list
  end

  def load_all_for(home)
    all = []
    done_ids = {}
    completed_on_map = {}
    stores_for(home).each do |si|
      idx = {
        active: index_section_ids(si[:index], "## Active"),
        abandoned: index_section_ids(si[:index], "## Abandoned"),
        completed: index_section_ids(si[:index], "## Completed"),
      }
      comp = completion_dates(si[:index])
      intent_dirs(si[:store]).each do |d|
        rec = parse_intent(si, d, idx)
        next unless rec
        rec[:completed_on] = comp[rec[:id]] || ""
        all << rec
        done_ids[[rec[:scope], rec[:id]]] = true if rec[:status] == "completed"
        completed_on_map[[rec[:scope], rec[:id]]] = comp[rec[:id]] if comp[rec[:id]] && !comp[rec[:id]].empty?
      end
    end
    referenced = {}
    all.each { |r| r[:sources].each { |s| referenced[[r[:scope], s]] = true } }
    [all, done_ids, referenced, completed_on_map]
  end

  def records_for(home)
    raw, done_ids, referenced, completed_on_map = load_all_for(home)
    raw.map { |r| classify(r, done_ids, referenced, completed_on_map) }
  end

  # --- fixture helpers ---------------------------------------------------------

  def blank_index
    "# Index\n\n## Active\n\n## Future\n\n## Completed\n\n## Abandoned\n"
  end

  def write_index(root, active: [], future: [], completed: [])
    lines = ->(rows) { rows.map { |id, slug, title| "- [#{id} - #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md) - tags" }.join("\n") }
    done_lines = completed.map { |id, slug, title, date| "- [#{id} - #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md) - #{date}" }.join("\n")
    File.write(File.join(root, "INDEX.md"), <<~IDX)
      # Index

      ## Active
      #{lines.call(active)}

      ## Future
      #{lines.call(future)}

      ## Completed
      #{done_lines}

      ## Abandoned
    IDX
  end

  def write_intent(store, id, slug, frontmatter, files: {})
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    fm = frontmatter.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.join(', ')}]" : v}" }.join("\n")
    File.write(File.join(dir, "#{id}--#{slug}.md"),
               "---\n#{fm}\n---\n\n## Intent\n#{frontmatter[:intent]}\n")
    files.each { |name, content| File.write(File.join(dir, name), content) }
    dir
  end

  def project_store(name)
    store = File.join(@home, "projects", name, "store")
    FileUtils.mkdir_p(store)
    write_index(File.join(@home, "projects", name))
    store
  end

  def lock_file(dir, mtime:, agent: "claude", session: "session12345678")
    path = File.join(dir, "delivery.lock")
    File.write(path, JSON.generate("owner_session" => session, "owner_agent" => agent,
                                    "owner_harness" => "claude", "owner_model" => "sonnet",
                                    "owner_thread" => "t1", "run_mode" => "auto"))
    File.utime(mtime, mtime, path)
  end

  def heartbeat(session_id, age_seconds:, now: NOW)
    dir = File.join(@home, "store", ".tmp", session_id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "heartbeat"), (now - age_seconds).utc.iso8601)
  end

  # --- D1: Active counts index active only, never future or completed ---------

  def test_active_counts_index_active_only
    store = project_store("demo")
    write_intent(store, "1", "future-one", { id: 1, intent: "Future thing", author: "agent",
                                              tags: [], created: "2026-06-01" })
    write_intent(store, "2", "active-one", { id: 2, intent: "Active thing", author: "agent",
                                              tags: [], created: "2026-06-01" })
    write_intent(store, "3", "done-one", { id: 3, intent: "Done thing", author: "agent",
                                            tags: [], created: "2026-06-01" }, files: { "outcome.md" => "done" })
    write_index(File.dirname(store), active: [["2", "active-one", "Active thing"]],
                future: [["1", "future-one", "Future thing"]],
                completed: [["3", "done-one", "Done thing", "2026-08-01"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    assert_equal 1, screen_active_count(scoped)
  end

  # --- D2: In delivery ignores stale locks -------------------------------------

  def test_in_delivery_ignores_stale_locks
    store = project_store("demo")
    fresh_dir = write_intent(store, "1", "fresh", { id: 1, intent: "Fresh lock", author: "agent",
                                                     tags: [], created: "2026-06-01" })
    stale_dir = write_intent(store, "2", "stale", { id: 2, intent: "Stale lock", author: "agent",
                                                     tags: [], created: "2026-06-01" })
    write_index(File.dirname(store),
                active: [["1", "fresh", "Fresh lock"], ["2", "stale", "Stale lock"]])
    lock_file(fresh_dir, mtime: NOW - 60)
    lock_file(stale_dir, mtime: NOW - 7200)

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    assert_equal 1, screen_in_delivery_count(scoped, now: NOW)
  end

  # --- D3: Delivered uses completion dates, never created ----------------------

  def test_delivered_uses_completion_dates
    store = project_store("demo")
    # A count-only assertion over two records can't tell "reads completion
    # dates" from "reads created dates": swapping the source just relabels
    # which single record counts, so a third record breaks the symmetry -
    # correct (completion-date) reading counts 2, created-date reading
    # counts only 1.
    #
    # completed_on INSIDE the window, created far OUTSIDE it: counted only
    # by the correct reading.
    write_intent(store, "1", "old-created-recent-done",
                 { id: 1, intent: "Old created, recent completion", author: "agent", tags: [],
                   created: "2026-01-01" },
                 files: { "outcome.md" => "done" })
    # completed_on OUTSIDE the window, created INSIDE it: counted only by a
    # created-date misread.
    write_intent(store, "2", "recent-created-old-done",
                 { id: 2, intent: "Recent created, old completion", author: "agent", tags: [],
                   created: "2026-09-04" },
                 files: { "outcome.md" => "done" })
    # completed_on INSIDE the window, created far OUTSIDE it: a second
    # record counted only by the correct reading, so the two readings can
    # never coincidentally agree on the total.
    write_intent(store, "3", "old-created-recent-done-2",
                 { id: 3, intent: "Old created, recent completion again", author: "agent", tags: [],
                   created: "2026-02-01" },
                 files: { "outcome.md" => "done" })
    write_index(File.dirname(store),
                completed: [["1", "old-created-recent-done", "Old created, recent completion", "2026-09-03"],
                            ["2", "recent-created-old-done", "Recent created, old completion", "2026-08-01"],
                            ["3", "old-created-recent-done-2", "Old created, recent completion again",
                             "2026-09-02"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    assert_equal 2, screen_delivered_count(scoped, now: NOW)
  end

  # --- D4: Roadmap field renders "none" without a roadmaps dir, no crash -------

  def test_roadmap_none_without_roadmaps
    project_store("demo")
    assert_equal "none", screen_roadmap_field(@home, "project:demo", now: NOW)
  end

  # --- D17: Roadmap shows the frontier batch when a real roadmap is live ------

  def test_roadmap_shows_frontier_batch_when_live
    project_store("demo")
    roadmaps_dir = File.join(@home, "projects", "demo", "roadmaps")
    FileUtils.mkdir_p(roadmaps_dir)
    File.write(File.join(roadmaps_dir, "demo-roadmap.md"), <<~MD)
      # Roadmap: demo-roadmap

      Test roadmap.

      ## Goal
      Test goal.

      ## Batches

      ### Wave A
      - [ ] 61 Some queued item - queued

      ## Log
      - 2026-09-01 09:00 UTC created
    MD

    assert_equal "demo-roadmap · Wave A", screen_roadmap_field(@home, "project:demo", now: NOW)
  end

  # --- D5: Sessions counts only fresh heartbeats -------------------------------

  def test_sessions_counts_fresh_heartbeats_only
    heartbeat("fresh-session", age_seconds: 60)
    heartbeat("dead-session", age_seconds: 7200)

    assert_equal 1, screen_sessions_count(@home, now: NOW)
  end

  # --- D16: Sessions includes the calling session's own live heartbeat --------

  def test_sessions_includes_calling_session_heartbeat
    heartbeat("caller-session", age_seconds: 30)
    with_env("CLAUDE_CODE_SESSION_ID" => "caller-session") do
      assert_equal 1, screen_sessions_count(@home, now: NOW)
    end
  end

  # --- D6: Where we are orders active records by last-touch descending --------

  def test_where_we_are_orders_by_last_touch_desc
    store = project_store("demo")
    write_intent(store, "1", "oldest", { id: 1, intent: "Oldest touch", author: "agent", tags: [],
                                          created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-01T08:00:00Z  How  touched\n" })
    write_intent(store, "2", "newest", { id: 2, intent: "Newest touch", author: "agent", tags: [],
                                          created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-04T08:00:00Z  Exec  touched\n" })
    write_intent(store, "3", "middle", { id: 3, intent: "Middle touch", author: "agent", tags: [],
                                          created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-02T08:00:00Z  Why  touched\n" })
    write_index(File.dirname(store),
                active: [["1", "oldest", "Oldest touch"], ["2", "newest", "Newest touch"],
                         ["3", "middle", "Middle touch"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    rows = screen_where_we_are(scoped, now: NOW)
    assert_equal %w[2 3 1], rows.map { |r| r[:graph_id] }
  end

  # --- D7: Where we go next matches render_json's dispatchable_queue order ----

  def test_next_matches_json_queue_order
    store = project_store("demo")
    # Rank order here is a full reversal of both id order and directory
    # (insertion) order, so a deleted sort_by cannot hide behind a fixture
    # that happens to already be in rank order.
    #
    # LOWEST id, low value, no flags -> ranks LAST.
    write_intent(store, "1", "small-bug",
                 { id: 1, intent: "Small bug", author: "agent", tags: %w[bugfix],
                   created: "2026-06-01" })
    # MIDDLE id, low value but an in-progress flag beats a plain low-value
    # entry -> ranks SECOND.
    write_intent(store, "2", "research-it",
                 { id: 2, intent: "Research a thing", author: "agent", tags: %w[research],
                   created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-07-01T08:00:00Z  Why  touched\n" })
    # HIGHEST id, high value AND an in-progress flag -> ranks FIRST.
    write_intent(store, "3", "quick-win",
                 { id: 3, intent: "Quick high value win", author: "agent", tags: [], value: "high",
                   created: "2026-06-01" },
                 files: { "plan.md" => "p", "checklist.md" => "- [ ] x\n",
                          "savepoint.md" => "2026-07-01T08:00:00Z  How  touched\n" })
    # TRIAGE (excluded): agent root, implementation, no plan -> low + big -> triage.
    write_intent(store, "4", "triage-me",
                 { id: 4, intent: "Triage candidate", author: "agent", tags: [], created: "2026-06-01" })
    write_index(File.dirname(store),
                future: [["1", "small-bug", "Small bug"], ["2", "research-it", "Research a thing"],
                         ["3", "quick-win", "Quick high value win"], ["4", "triage-me", "Triage candidate"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    json_queue = render_json(scoped, "project:demo")[:dispatchable_queue]
    rows = screen_where_we_go_next(scoped)

    assert_equal %w[3 2 1], json_queue.map { |r| r[:id] }, "fixture sanity: expected rank order"
    assert_equal json_queue.map { |r| r[:id] }, rows.map { |r| r[:intent] }
    assert_equal json_queue.map { |r| r[:rank] }, rows.map { |r| r[:rank] }
  end

  # --- D8: Where we are caps at 8, Where we go next caps at 6 -----------------

  def test_caps_apply
    store = project_store("demo")
    active_rows = (1..10).map do |i|
      write_intent(store, "a#{i}", "active-#{i}", { id: "a#{i}", intent: "Active #{i}", author: "agent",
                                                     tags: [], created: "2026-06-01" },
                   files: { "savepoint.md" => "2026-09-0#{[i, 9].min}T08:00:00Z  How  touched\n" })
      ["a#{i}", "active-#{i}", "Active #{i}"]
    end
    next_rows = (1..8).map do |i|
      write_intent(store, "b#{i}", "next-#{i}", { id: "b#{i}", intent: "Next #{i}", author: "agent",
                                                   tags: %w[bugfix], created: "2026-06-01" })
      ["b#{i}", "next-#{i}", "Next #{i}"]
    end
    write_index(File.dirname(store), active: active_rows, future: next_rows)

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    assert_equal 8, screen_where_we_are(scoped, now: NOW).size
    assert_equal 6, screen_where_we_go_next(scoped).size
  end

  # --- D9: render_screen is byte-identical on the same store + injected now ---

  def test_render_screen_is_byte_identical
    store = project_store("demo")
    # A5: two calls sharing the SAME injected now: stay byte-identical even
    # if a helper secretly reads Time.now instead of the parameter - two
    # calls a few milliseconds apart almost never straddle a freshness
    # boundary, so a plain byte-identical comparison can't tell the two
    # apart. Placing the injected clock far from the real wall clock closes
    # that gap: a Time.now leak then reads this fixture's lock and heartbeat
    # (fresh only near fixed_now) as many months stale, changing the counted
    # values rather than merely risking a race.
    fixed_now = Time.utc(2026, 1, 1, 12, 0, 0)
    dir = write_intent(store, "1", "active-one", { id: 1, intent: "Active thing", author: "agent", tags: [],
                                                    created: "2025-12-01" },
                        files: { "savepoint.md" => "2025-12-31T08:00:00Z  How  touched\n" })
    write_index(File.dirname(store), active: [["1", "active-one", "Active thing"]])
    lock_file(dir, mtime: fixed_now - 60)
    heartbeat("session-abc", age_seconds: 60, now: fixed_now)

    records = records_for(@home)
    first = render_screen(records, "project:demo", plastic_home: @home, now: fixed_now)
    second = render_screen(records, "project:demo", plastic_home: @home, now: fixed_now)
    assert_equal first, second

    fields = screen_fields(records, "project:demo", plastic_home: @home, now: fixed_now)
    assert_equal 1, fields[:in_delivery], "the fixture's lock is fresh only under the injected clock"
    assert_equal 1, fields[:sessions], "the fixture's heartbeat is fresh only under the injected clock"
  end

  # --- D10: the global scope renders without a project-only helper crashing --

  def test_global_scope_renders
    # An opener-only assertion passes even if the `scope == "global"`
    # short-circuit is dropped from screen_scoped_records or
    # screen_tier_root, since the header string comes straight from
    # fields.fetch(:scope). Prove correct aggregation instead: seed TWO
    # project stores plus a roadmap that lives at the GLOBAL tier (never a
    # per-project one), and assert on data only a correct global read can
    # produce.
    store_a = project_store("proj-a")
    store_b = project_store("proj-b")
    write_intent(store_a, "1", "alpha", { id: 1, intent: "Alpha work", author: "agent", tags: [],
                                           created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-01T08:00:00Z  How  touched\n" })
    write_intent(store_b, "2", "beta", { id: 2, intent: "Beta work", author: "agent", tags: [],
                                          created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-02T08:00:00Z  Why  touched\n" })
    write_index(File.dirname(store_a), active: [["1", "alpha", "Alpha work"]])
    write_index(File.dirname(store_b), active: [["2", "beta", "Beta work"]])

    # Lives directly under @home (the global tier root), NOT under
    # @home/projects/global - the path screen_tier_root would derive if its
    # own "global" short-circuit were dropped.
    roadmaps_dir = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(roadmaps_dir)
    File.write(File.join(roadmaps_dir, "global-roadmap.md"), <<~MD)
      # Roadmap: global-roadmap

      Test roadmap.

      ## Goal
      Test goal.

      ## Batches

      ### Wave G
      - [ ] 71 Some queued item - queued

      ## Log
      - 2026-09-01 09:00 UTC created
    MD

    records = records_for(@home)
    text = render_screen(records, "global", plastic_home: @home, now: NOW)
    assert_match(/\A## ▶ global · dashboard/, text)

    fields = screen_fields(records, "global", plastic_home: @home, now: NOW)
    assert_equal 2, fields[:active], "global Active must sum across every store, not just one"
    assert_equal %w[2 1], fields[:where_we_are].map { |r| r[:intent][/\A(\S+)/, 1] },
                 "Where we are must carry intents from both projects"
    assert_equal "global-roadmap · Wave G", fields[:roadmap],
                 "the global tier root, not a projects/global path, must be read"
  end

  # --- D12: Where we go next excludes drive and triage dispositions -----------

  def test_next_excludes_drive_and_triage_dispositions
    store = project_store("demo")
    # NEXT BIG THING (drive): human root, implementation, no plan -> high + big.
    write_intent(store, "1", "drive-candidate",
                 { id: 1, intent: "Drive candidate ranked top", author: "human", tags: [],
                   created: "2026-06-01" })
    # DEFER (included): bugfix -> low + small.
    write_intent(store, "2", "defer-candidate",
                 { id: 2, intent: "Defer candidate", author: "agent", tags: %w[bugfix],
                   created: "2026-06-01" })
    write_index(File.dirname(store),
                future: [["1", "drive-candidate", "Drive candidate ranked top"],
                         ["2", "defer-candidate", "Defer candidate"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    rows = screen_where_we_go_next(scoped)

    refute_includes rows.map { |r| r[:intent] }, "1"
    assert_includes rows.map { |r| r[:intent] }, "2"
  end

  # --- D13: the What column escapes a literal pipe and truncates a long title -

  def test_next_what_escapes_pipes_and_truncates
    store = project_store("demo")
    long_title = "A title with a | pipe and " + ("many extra words " * 10)
    write_intent(store, "1", "piped",
                 { id: 1, intent: long_title, author: "agent", tags: %w[bugfix], created: "2026-06-01" })
    write_index(File.dirname(store), future: [["1", "piped", "Piped"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    rows = screen_where_we_go_next(scoped)
    row = rows.find { |r| r[:intent] == "1" }
    refute_nil row

    rendered = "| #{row[:rank]} | #{row[:intent]} | #{row[:what]} | #{row[:why]} |"
    without_escapes = rendered.gsub('\\|', "")
    assert_equal 5, without_escapes.count("|"), "an unescaped pipe must not add a column: #{rendered.inspect}"
    assert_match(/…\z/, row[:what])
    refute_operator row[:what].length, :>, 120
  end

  # --- D14: a stale lock's Lead reads "not recorded", never a named lead -----

  def test_lead_not_recorded_on_stale_lock
    store = project_store("demo")
    dir = write_intent(store, "1", "stale-active",
                        { id: 1, intent: "Stale active intent", author: "agent", tags: [],
                          created: "2026-06-01" },
                        files: { "savepoint.md" => "2026-09-01T08:00:00Z  How  touched\n" })
    write_index(File.dirname(store), active: [["1", "stale-active", "Stale active intent"]])
    lock_file(dir, mtime: NOW - 7200, agent: "claude", session: "session12345678")

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    assert_equal 0, screen_in_delivery_count(scoped, now: NOW)
    row = screen_where_we_are(scoped, now: NOW).first
    assert_equal "not recorded", row[:lead]
    refute_match(/claude/i, row[:lead])
  end

  # --- D15: --ansi respects NO_COLOR and the non-tty guard --------------------

  CLI = File.expand_path("../scripts/dashboard.rb", __dir__)

  def test_ansi_respects_no_color_and_tty_guard
    store = project_store("demo")
    write_intent(store, "1", "active-one", { id: 1, intent: "Active thing", author: "agent", tags: [],
                                              created: "2026-06-01" })
    write_index(File.dirname(store), active: [["1", "active-one", "Active thing"]])

    out, err, status = Open3.capture3({ "PLASTIC_HOME" => @home }, "ruby", CLI, "project", "demo",
                                       "--screen", "--ansi")
    assert_equal 0, status.exitstatus, err
    refute_match(/\e\[/, out, "a non-tty pipe without the force seam must stay plain")

    out, err, status = Open3.capture3({ "PLASTIC_HOME" => @home, "PLASTIC_FORCE_COLOR" => "1" },
                                       "ruby", CLI, "project", "demo", "--screen", "--ansi")
    assert_equal 0, status.exitstatus, err
    assert_match(/\e\[/, out, "PLASTIC_FORCE_COLOR=1 must paint")

    out, err, status = Open3.capture3({ "PLASTIC_HOME" => @home, "PLASTIC_FORCE_COLOR" => "1",
                                         "NO_COLOR" => "1" }, "ruby", CLI, "project", "demo",
                                       "--screen", "--ansi")
    assert_equal 0, status.exitstatus, err
    refute_match(/\e\[/, out, "NO_COLOR must force plain even under the force seam")
  end

  # --- intent 331d1: ruled column vocabulary (Graph ID / Intent / Reason) -----

  # Reads the header row printed directly under a "**<heading>**" section, so
  # a check against it proves the RENDERED header, never the whole text
  # (V3 needs exactly this: a legitimate title may contain the word "What").
  def header_cells(text, heading)
    lines = text.lines.map(&:chomp)
    start = lines.index { |l| l.strip == "**#{heading}**" }
    refute_nil start, "expected a #{heading.inspect} section in:\n#{text}"
    header_line = lines[(start + 1)..].find { |l| l.start_with?("|") }
    refute_nil header_line, "expected a header row under #{heading.inspect}"
    header_line.split("|").map(&:strip).reject(&:empty?)
  end

  def test_where_we_are_headers_are_ruled_vocabulary # V1
    project_store("demo")
    text = render_screen(records_for(@home), "project:demo", plastic_home: @home, now: NOW)
    assert_equal ["Graph ID", "Intent", "Stage", "Progress", "Lead"], header_cells(text, "Where we are")
  end

  def test_where_we_go_next_headers_are_ruled_vocabulary # V2
    project_store("demo")
    text = render_screen(records_for(@home), "project:demo", plastic_home: @home, now: NOW)
    assert_equal ["Rank", "Graph ID", "Intent", "Reason"], header_cells(text, "Where we go next")
  end

  def test_no_column_is_named_what # V3
    store = project_store("demo")
    write_intent(store, "1", "title-with-what",
                 { id: 1, intent: "What are we doing here", author: "agent", tags: %w[bugfix],
                   created: "2026-06-01" })
    write_index(File.dirname(store), future: [["1", "title-with-what", "What are we doing here"]])

    text = render_screen(records_for(@home), "project:demo", plastic_home: @home, now: NOW)
    headers = header_cells(text, "Where we are") + header_cells(text, "Where we go next")
    refute_includes headers, "What"
    assert_includes text, "What are we doing here",
                    "sanity: a legitimate title may still contain the word, just never as a header"
  end

  def test_graph_id_column_carries_the_bare_id # V4
    store = project_store("demo")
    write_intent(store, "42", "some-slug", { id: 42, intent: "Some intent title", author: "agent",
                                              tags: [], created: "2026-06-01" })
    write_index(File.dirname(store), active: [["42", "some-slug", "Some intent title"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    row = screen_where_we_are(scoped, now: NOW).first
    assert_equal "42", row[:graph_id]
    refute_match(/\A42\b/, row[:intent])
  end

  def test_intent_column_takes_the_pre_colon_lead # V5
    store = project_store("demo")
    write_intent(store, "1", "colon-title",
                 { id: 1, intent: "Dashboard screen: everything after the colon", author: "agent",
                   tags: [], created: "2026-06-01" })
    write_index(File.dirname(store), active: [["1", "colon-title", "Dashboard screen: everything after the colon"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    row = screen_where_we_are(scoped, now: NOW).first
    assert_equal "Dashboard screen", row[:intent]
    refute_includes row[:intent], "everything after the colon"
  end

  def test_intent_column_renders_a_colonless_title_whole # V6
    store = project_store("demo")
    write_intent(store, "1", "no-colon", { id: 1, intent: "A colonless title", author: "agent",
                                            tags: [], created: "2026-06-01" })
    write_index(File.dirname(store), active: [["1", "no-colon", "A colonless title"]])

    scoped = screen_scoped_records(records_for(@home), "project:demo")
    row = screen_where_we_are(scoped, now: NOW).first
    assert_equal "A colonless title", row[:intent]
    refute_empty row[:intent]
  end

  def test_no_rendered_row_exceeds_115_columns # V7
    store = project_store("demo")
    long_title = "A very long intent title that goes on and on and on " * 5
    write_intent(store, "1", "long-active", { id: 1, intent: long_title, author: "agent", tags: [],
                                               created: "2026-06-01" },
                 files: { "savepoint.md" => "2026-09-01T08:00:00Z  How  touched\n" })
    write_intent(store, "2", "long-next", { id: 2, intent: long_title, author: "agent",
                                             tags: %w[bugfix], created: "2026-06-01" })
    write_index(File.dirname(store), active: [["1", "long-active", "Long"]],
                future: [["2", "long-next", "Long"]])

    text = render_screen(records_for(@home), "project:demo", plastic_home: @home, now: NOW)
    data_rows = text.lines.map(&:chomp).select { |l| l.start_with?("|") && !l.start_with?("| ---") }
    refute_empty data_rows
    data_rows.each { |line| assert_operator line.length, :<=, 115, "row exceeded budget: #{line.inspect}" }
  end

  private

  def with_env(vars)
    old = {}
    vars.each { |k, v| old[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
