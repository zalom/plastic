# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "json"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/screen_paint"
require_relative "../scripts/lib/lock"
require_relative "../scripts/dashboard"

# Intent 331a2 (D5, S4): mirror scripts/report-screen's own glob explicitly rather than relying
# on the kind registry being populated incidentally through dashboard.rb's require chain, so a
# future require reshuffle cannot silently shrink the registry this census tests against.
Dir.glob(File.join(File.expand_path("../scripts/lib/screens", __dir__), "*.rb")).sort.each { |f| require_relative f }

# Intent 331f1: the acceptance rule this intent adds - ScreenPaint.display_columns (ANSI
# stripped, every character at or above U+1100 counts two columns, everything else one) is
# the one bound every rendered row is measured against, replacing the character-count check
# the plan review found insufficient (a bar row can pass String#length while over the real
# 115-column bound). W1-W5e prove the field-table fitter's invariants (label/separator never
# truncate, value shrinks before note, note drops whole under an 8-column floor, a bar cell is
# never cut, the ellipsis reserves its own two-column display width, the row backstop never
# stacks a second ellipsis). W7-W7b prove the painted/plain data-table shrink picks the widest
# TEXT column and never crosses a header/id/bar floor. W6/W9 sweep all ten verbs (state,
# roster, session, delivered, delay, plan, roadmap plan/state/delivered, dashboard) on one
# fixture store carrying 300-character goals, titles, and notes plus a real progress bar, and
# prove every rendered row - plain and painted - stays at or under 115 display columns.
class ScreenWidthTest < Minitest::Test
  NOW = Time.utc(2026, 9, 5, 12, 0, 0)
  REPO = File.expand_path("..", __dir__)

  def setup
    @home = Dir.mktmpdir("screen-width")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture helpers, matching test/report_screen_header_and_width_test.rb and
  # test/dashboard_screen_test.rb's own conventions rather than inventing new ones ----------

  def tier_root
    root = File.join(@home, "projects", "demo")
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, active:, completed:)
    active_lines = active.map { |id, title| "- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags" }.join("\n")
    completed_lines = completed.map { |id, title, date| "- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - #{date}" }.join("\n")
    File.write(File.join(root, "INDEX.md"), <<~MD)
      # Index

      ## Active
      #{active_lines}

      ## Future

      ## Completed
      #{completed_lines}

      ## Abandoned
    MD
  end

  def make_intent(root, id:, title:, checklist:, savepoint:, insight: "", outcome_body: nil)
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--slug.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "#{title}"
      sources: []
      chain: []
      created: 2026-08-30
      author: human
      tags: []
      ---

      ## Intent
      #{title}

      ## Context

      ## Outcome

      ## Insights
      #{insight}
    MD
    File.write(File.join(dir, "checklist.md"), checklist)
    File.write(File.join(dir, "savepoint.md"), savepoint)
    File.write(File.join(dir, "outcome.md"), outcome_body) if outcome_body
    dir
  end

  # W9a: a fresh delivery lock so ReportScreen.lead_cell renders "agent - session" rather than
  # "idle" - the mtime is pinned to just before NOW (not real wall-clock time) so freshness
  # never depends on when the suite actually runs.
  def write_fresh_lock(dir, agent:, session:)
    path = File.join(dir, "delivery.lock")
    File.write(path, JSON.generate("owner_session" => session, "owner_harness" => "claude",
                                    "owner_agent" => agent, "owner_model" => "sonnet",
                                    "owner_thread" => "main", "run_mode" => "auto"))
    File.utime(NOW - 60, NOW - 60, path)
  end

  HOW_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze
  DONE_LEDGER = "2026-08-30T12:00:00Z  What  19--slug.md\n2026-08-30T13:51:42Z  Done  delivered\n".freeze

  LONG_TITLE = (["Title"] * 60).join(" ").freeze
  LONG_GOAL = (["Goal"] * 60).join(" ").freeze
  LONG_STEP = (["StepWord"] * 40).join(" ").freeze
  LONG_INSIGHT = (["InsightWord"] * 40).join(" ").freeze
  LONG_NOTE = ("D" * 300).freeze

  # dashboard.rb's own record pipeline, re-derived from an explicit `home` rather than the
  # ambient PLASTIC_HOME constant (test/dashboard_screen_test.rb's stores_for/load_all_for,
  # copied rather than reinvented).
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

  def records_for(home)
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
    all.map { |r| classify(r, done_ids, referenced, completed_on_map) }
  end

  # One heavy fixture (300-character goal/title/notes, a real progress bar in a field
  # table's value column) rendered through all ten verbs. Reproduces the RC1-RC4 defects
  # spec.md measured on alpha 5839f3f: roadmap state's field labels mangle to "**Progr…" etc,
  # its separator row collapses to "| -------- |…", and the Batches table carries no Intent
  # column.
  def build_all_screens
    root = tier_root
    templates = File.join(REPO, "templates")

    checklist12 = "# Checklist\n\n- [x] S1 short step done\n- [ ] S2 #{LONG_STEP}\n"
    write_index(root, active: [["12", LONG_TITLE]], completed: [["19", "Demo delivered", "2026-09-04"]])

    dir12 = make_intent(root, id: "12", title: LONG_TITLE, checklist: checklist12, savepoint: HOW_LEDGER,
                         insight: "2026-09-01T00:00:00Z  #{LONG_INSIGHT}")
    dir19 = make_intent(root, id: "19", title: "Demo delivered", checklist: "# Checklist\n\n- [x] S1 done\n",
                         savepoint: DONE_LEDGER, outcome_body: <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Delivered
      | Row | What |
      | --- | --- |
      | S1 | #{LONG_NOTE} |

      ## Needs you
      | N | What | Why |
      | --- | --- | --- |
      | N1 | #{"D" * 80} | #{"x" * 10} |
      | N2 | #{"x" * 10} | #{"D" * 80} |
    MD

    # W9a: ten Batches rows with heterogeneous Status and Lead lengths, the live store's own
    # shape (P2's actual failure: painted `roadmap state` at 116 columns). 20 and 21 carry a
    # fresh delivery lock each, with agent names of different lengths, so the Lead column is
    # never a single repeated width; 22-27 have no intent directory at all (an "idle" Lead),
    # and the five raw statuses plus "delivering"/"delivered" span the full STATUSES length
    # range (6 to 10 characters).
    dir20 = make_intent(root, id: "20", title: "Short title one", checklist: "# Checklist\n\n- [ ] S1 open\n",
                         savepoint: HOW_LEDGER)
    dir21 = make_intent(root, id: "21", title: "A somewhat longer intent title here",
                         checklist: "# Checklist\n\n- [ ] S1 open\n", savepoint: HOW_LEDGER)
    dir22 = make_intent(root, id: "22", title: "Another intent with a mid length title",
                         checklist: "# Checklist\n\n- [ ] S1 open\n", savepoint: HOW_LEDGER)
    write_fresh_lock(dir20, agent: "executor", session: "sess-2020-aaaa")
    write_fresh_lock(dir21, agent: "plastic-enforcer-fix-round-two", session: "sess-2121-bbbb")

    roadmaps_dir = File.join(root, "roadmaps")
    FileUtils.mkdir_p(roadmaps_dir)
    roadmap_path = File.join(roadmaps_dir, "demo.md")
    File.write(roadmap_path, <<~MD)
      # Roadmap: Demo
      ## Goal
      #{LONG_GOAL}.
      ## Batches
      ### Batch 1
      - [ ] 12 #{LONG_TITLE} - delivering
      - [x] 19 Demo delivered - delivered
      - [ ] 20 Short title one - queued
      - [ ] 21 A somewhat longer intent title here - blocked
      - [ ] 22 Another intent with a mid length title - abandoned
      ### Batch 2
      - [ ] 23 Yet another intent title of a medium length - delivering
      - [ ] 24 Short - queued
      - [ ] 25 Delivered already, a rather descriptive title - delivered
      - [ ] 26 Blocked intent with a fairly long descriptive title - blocked
      - [ ] 27 Final queued intent in the batch - queued
      ## Log
      - 2026-09-01 00:00 UTC created.
    MD

    screens = {}
    screens["state"] = ReportScreen.render_state(intent_dir: dir12, store_root: root, changed: nil,
                                                  template: File.read(File.join(templates, "report-state.md")))
    screens["plan"] = ReportScreen.render_plan(intent_dir: dir12, store_root: root,
                                                template: File.read(File.join(templates, "report-plan.md")))
    screens["roster"] = ReportScreen.render_roster(root)
    screens["delivered"] = ReportScreen.render_delivered(intent_dir: dir19)
    screens["delay"] = ReportScreen.render_delay(intent_dir: dir19)
    screens["session"] = ReportScreen.render_session(dirs: [dir19], skipped: 0, store_root: root)
    screens["roadmap plan"] = ReportScreen.render_roadmap(path: roadmap_path, verb: "plan", store_root: root)
    screens["roadmap state"] = ReportScreen.render_roadmap(path: roadmap_path, verb: "state", store_root: root, now: NOW)
    screens["roadmap delivered"] = ReportScreen.render_roadmap(path: roadmap_path, verb: "delivered", store_root: root)
    screens["dashboard"] = render_screen(records_for(@home), "project:demo", plastic_home: @home, now: NOW)
    # 331a2 (D5, S2 leg 3): the eleventh verb. The :intent kind has been registered since
    # screen_paint.rb:543 and fed to the hook (test/hook_message_display_test.rb:89), but this
    # census never rendered it - a new key, added here without touching any of the ten already
    # measured above. dir19 (a short title), not dir12 (LONG_TITLE): IntentScreen.render never
    # calls ReportScreen.fit_screen, so a 300-character title here would blow the 115-column
    # bound on a pre-existing gap this action's kill criterion puts out of scope - a renderer
    # change, not a classify grammar rule.
    screens["intent"] = IntentScreen.render(intent_dir: dir19, store_root: root,
                                             template: File.read(File.join(templates, "intent-screen.md")))
    screens
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  # ==========================================================================================
  # 331a2 (D5): the screen census GUARD. Every defect this guard exists to catch (331a1's two
  # grammar gaps, 331f1's two width gaps) shipped invisible to the ten-verb happy-path census
  # above, because its fixtures never fired a renderer's conditional branches: one delivered
  # dir, skipped: 0. This section widens the SAME census - every fixture below feeds the
  # classifier the HOOK actually calls (message_display.rb:475-483: find the first opener,
  # walk one region over the WHOLE reply), not the CLI's per-block painting, which can never
  # fail this way.
  # ==========================================================================================

  # --- S2: the derived site table, kept alive as running assertions rather than a comment ----
  #
  # Leg 1: `grep -n '<< "' scripts/lib/report_screen.rb` (47 sites at 4e4b96e) and the same
  # over scripts/dashboard.rb (42 sites, all outside the painter's path - dashboard.rb has no
  # painted-screen emission at all; DashboardScreen.render builds the dashboard SCREEN by
  # substitution and has zero `<<` sites of its own).
  #
  # Leg 2: `grep -n '<<' report_screen.rb | grep -v '<< "' | grep -v '<<~'` (28 hits) misses
  # five sites that append a method call or constant rather than a literal, and two of those
  # five are exactly F5's own shape:
  #   973  collapsed_open_steps_note - "N open" / "N open · showing the first three" (:count)
  #   1052 NOT_RECORDED when Evidence is empty (:closer)
  #   1460 the session `note:` block, free text ABOVE the first opener (T2)
  #   1466 the rescue card `## <id> · could not render (<msg>)` - :unknown today (F5)
  #   1478 the roster, appended to every session report (:opener + roster grammar)
  #
  # Leg 3: seven screen templates built by substitution (zero `<<` sites): intent-screen.md,
  # report-state.md, report-plan.md, dashboard-screen.md, and the three report-roadmap-*.md
  # templates. `intent-screen.md` is the one this action adds as an eleventh verb.
  def literal_append_lines(path)
    File.readlines(path).each_with_index.select { |line, _| line.include?('<< "') }.map { |_, i| i + 1 }
  end

  def non_literal_append_lines(path)
    File.readlines(path).each_with_index
        .select { |line, _| line.include?("<<") && !line.include?('<< "') && !line.include?("<<~") }
        .map { |_, i| i + 1 }
  end

  def test_leg1_report_screen_literal_append_count_matches_the_repo
    assert_equal 47, literal_append_lines(File.join(REPO, "scripts", "lib", "report_screen.rb")).length,
                 "the derived site table's leg 1 count has drifted from the repo - re-derive it " \
                 "before trusting the rest of this file's fixtures"
  end

  def test_leg1_dashboard_literal_append_count_is_the_exemption_bound
    assert_equal 42, literal_append_lines(File.join(REPO, "scripts", "dashboard.rb")).length,
                 "dashboard.rb's literal-append count is the exemption bound the board tests below assert against"
  end

  def test_leg2_non_literal_append_sites_include_every_screen_emission
    lines = non_literal_append_lines(File.join(REPO, "scripts", "lib", "report_screen.rb"))
    assert_equal 28, lines.length,
                 "the derived site table's leg 2 count has drifted from the repo - re-derive it"
    # Re-derived 2026-09-05 when 322 merged into alpha: 322 adds code above these
    # sites, so every one shifted by the same offset (973->1012, 1052->1091,
    # 1460->1499, 1466->1505, 1478->1517). Same five sites, matched by content.
    [1012, 1091, 1499, 1505, 1517].each do |line|
      assert_includes lines, line, "leg 2 must still carry the screen-emitting non-literal append at line #{line}"
    end
  end

  def test_screen_paint_is_called_from_exactly_three_places
    callers = %w[report-screen dashboard.rb message_display.rb].flat_map do |base|
      path = Dir.glob(File.join(REPO, "scripts", "**", base)).find { |f| File.file?(f) }
      File.readlines(path).each_with_index.select { |line, _| line.include?("ScreenPaint.paint(") }
    end
    assert_equal 3, callers.length,
                 "every ScreenPaint.paint caller must be accounted for - a new one needs this census's coverage too"
  end

  # --- fixtures the ten-verb happy-path census never fired -----------------------------------

  # F1/F2/F4/T1/T3: two SHORT delivered dirs (deliberately not dir19's 300-character LONG_NOTE
  # content - S4 warns a second dir carrying that content is the obvious way to blow the
  # 115-column bound for the wrong reason). DONE_LEDGER on both dirs reproduces the exact meta
  # line the plan review measured: "2026-08-30 13:51 UTC · not recorded · 1 h 51 min · not
  # recorded".
  def two_delivered_dirs_session_text(skipped: 0, tag_reader: ->(_dir) { nil })
    root = tier_root
    write_index(root, active: [], completed: [["40", "Short A"], ["41", "Short B"]])
    dir_a = make_intent(root, id: "40", title: "Short A", checklist: "# Checklist\n\n- [x] S1 done\n", savepoint: DONE_LEDGER)
    dir_b = make_intent(root, id: "41", title: "Short B", checklist: "# Checklist\n\n- [x] S1 done\n", savepoint: DONE_LEDGER)
    ReportScreen.render_session(dirs: [dir_a, dir_b], skipped: skipped, store_root: root, tag_reader: tag_reader)
  end

  # F5/T3: the raising dir is the SECOND one. Prior art (report_screen_session_test.rb:873)
  # raises for the FIRST dir, which the plan review proved is the wrong order - with no opener
  # above the cards, first_rejected returns nil no matter what the grammar says.
  def rescue_card_session_text
    root = tier_root
    write_index(root, active: [], completed: [["70", "First"], ["71", "Second boom"]])
    dir_first = make_intent(root, id: "70", title: "First", checklist: "# Checklist\n\n- [x] S1 done\n", savepoint: DONE_LEDGER)
    dir_second = make_intent(root, id: "71", title: "Second boom", checklist: "# Checklist\n\n- [x] S1 done\n", savepoint: DONE_LEDGER)
    boom = ->(d) { raise "boom" if d == dir_second }
    ReportScreen.render_session(dirs: [dir_first, dir_second], skipped: 0, store_root: root, tag_reader: boom)
  end

  # T2: render_session emits three lines the region walk can never reach - the `note:` block,
  # the empty-session closer, and the skip note - because with `dirs: []` they sit ABOVE the
  # roster's opener. A live intent keeps the roster non-empty so an opener still exists
  # somewhere in the reply, matching the plan review's own measured shape (first opener at
  # index 4, lines 0-3 never walked).
  def zero_dirs_session_text(skipped:, note: nil)
    root = tier_root
    write_index(root, active: [["50", "Live intent"]], completed: [])
    make_intent(root, id: "50", title: "Live intent", checklist: "# Checklist\n\n- [ ] S1 open\n", savepoint: HOW_LEDGER)
    ReportScreen.render_session(dirs: [], skipped: skipped, store_root: root, note: note)
  end

  # S2 leg 2 line 973, both forks: an intent with <=3 open items prints "N open"; one with >3
  # prints "N open · showing the first three". A roster with several collapsed blocks is also
  # the fixture spec.md's F2 note explicitly DROPS from the F2 proof: its blocks classify
  # under :field/:step, independent of opener_idx, and carry no meta line at all.
  def roster_with_multiple_blocks_text
    root = tier_root
    write_index(root, active: [["60", "One open item"], ["61", "Two open items"], ["62", "Four open items"]], completed: [])
    make_intent(root, id: "60", title: "One open item", checklist: "# Checklist\n\n- [ ] S1 open\n", savepoint: HOW_LEDGER)
    make_intent(root, id: "61", title: "Two open items", checklist: "# Checklist\n\n- [ ] S1 open\n- [ ] S2 open\n", savepoint: HOW_LEDGER)
    make_intent(root, id: "62", title: "Four open items",
                checklist: "# Checklist\n\n- [ ] S1 open\n- [ ] S2 open\n- [ ] S3 open\n- [ ] S4 open\n", savepoint: HOW_LEDGER)
    ReportScreen.render_roster(root)
  end

  def opener_titles(text)
    text.lines.select { |l| ScreenPaint.classify(l) == :opener }.map { |l| l.strip.sub(/\A## /, "") }
  end

  # Acceptance 1: the HOOK path. Walk from the FIRST opener over the WHOLE reply - exactly
  # finalize() does at message_display.rb:475-483 - and name the offending line when the
  # grammar rejects one. Both first_rejected AND region_end are asserted (T1): the plan review
  # proved they carry SEPARATE copies of the nearest-opener rule, so mutating only one leaves
  # the other green.
  def assert_region_covers_the_whole_reply(verb, text)
    lines = text.lines
    start_idx = lines.index { |l| ScreenPaint.classify(l) == :opener }
    refute_nil start_idx, "#{verb}: no opener line found to anchor the hook's region walk"

    rejected = ScreenPaint.first_rejected(lines, start_idx)
    assert_nil rejected,
               "#{verb}: first_rejected named line #{rejected && rejected[0]} - #{rejected && rejected[1].inspect}"

    region_end = ScreenPaint.region_end(lines, start_idx)
    assert_equal lines.length, region_end,
                 "#{verb}: region_end stopped at #{region_end} of #{lines.length} - " \
                 "offending line: #{lines[region_end].to_s.chomp.inspect}"
  end

  # F1, F2, F5, T2 (passthrough), and the F2 roster fixture's grammar coverage - every verb
  # the ten-verb census already renders, plus every conditional fixture that census's
  # happy-path data never fired.
  def test_census_region_walk_covers_every_verb_over_conditional_fixtures
    build_all_screens.each { |verb, text| assert_region_covers_the_whole_reply(verb, text) }

    assert_region_covers_the_whole_reply("session skipped singular", two_delivered_dirs_session_text(skipped: 1))
    assert_region_covers_the_whole_reply("session skipped plural", two_delivered_dirs_session_text(skipped: 2))
    assert_region_covers_the_whole_reply("session two delivered dirs", two_delivered_dirs_session_text(skipped: 0))
    assert_region_covers_the_whole_reply("session rescue card", rescue_card_session_text)
    assert_region_covers_the_whole_reply("session note above the opener",
                                          zero_dirs_session_text(skipped: 0, note: "Some free-form note the model wrote."))
    assert_region_covers_the_whole_reply("roster multi-block", roster_with_multiple_blocks_text)
  end

  # Acceptance 3 / T2: lines a renderer emits ABOVE the first opener are invisible to the
  # region walk (dirs: [] puts them there), so they get a direct ScreenPaint.classify
  # assertion instead of walk coverage the census does not actually have.
  def test_lines_above_the_first_opener_are_classified_directly
    assert_equal :closer, ScreenPaint.classify("No intents delivered in this session.")
    assert_equal :count, ScreenPaint.classify("1 completed intent skipped: no Done bookend in savepoint.md.")
    assert_equal :count, ScreenPaint.classify("3 completed intents skipped: no Done bookend in savepoint.md.")
  end

  # F4: a region can classify fully and still lose content in paint. Every opener title a
  # renderer genuinely emits must survive, verbatim, into the painted output. Short titles
  # only (not the ten-verb census's 300-character LONG_TITLE fixtures), so a legitimate
  # width-fitter truncation is never mistaken for the genuine loss this assertion exists to
  # catch.
  def test_every_opener_title_survives_painting
    fixtures = {
      "two delivered dirs" => two_delivered_dirs_session_text(skipped: 0),
      "roster multi-block" => roster_with_multiple_blocks_text,
    }
    fixtures.each do |verb, text|
      titles = opener_titles(text)
      refute_empty titles, "#{verb}: fixture must carry at least one opener title to prove survival"
      painted = strip_ansi(ScreenPaint.paint(text, color: true).to_s)
      titles.each do |title|
        assert_includes painted, title, "#{verb}: opener title #{title.inspect} did not survive into the painted output"
      end
    end
  end

  # The dashboard.rb exemption, asserted rather than claimed (S2): the five board renderers -
  # the TTY board and the plain fallbacks - never carry a registered opener. If anyone later
  # gives a board an opener, this fails loudly instead of rotting into a blind spot.
  def test_dashboard_board_renderers_are_exempt_from_the_painter
    fixtures = {
      "continue" => render_continue([]),
      "project" => render_project([], "demo"),
      "all" => render_all([]),
      "plain project" => render_plain_project([], "demo"),
      "plain global" => render_plain_global([]),
    }
    fixtures.each do |board, text|
      first_line = text.lines.map(&:strip).find { |l| !l.empty? }
      assert_nil ScreenPaint.opener_kind(first_line.to_s),
                 "#{board}: a board renderer must never gain a registered opener silently: #{first_line.inspect}"
      assert_nil ScreenPaint.paint(text), "#{board}: a board renderer's output must never be claimed by the painter"
    end
  end

  # --- W6/W9: all ten verbs, plain and painted, bounded in DISPLAY COLUMNS -----------------

  def test_plain_rows_fit_every_verb
    build_all_screens.each do |verb, screen|
      screen.each_line do |line|
        assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                         "#{verb}: row over 115 display columns: #{line.inspect}"
      end
    end
  end

  def test_painted_rows_fit_every_verb
    build_all_screens.each do |verb, screen|
      painted = ScreenPaint.paint(screen, color: true)
      refute_nil painted, "#{verb}: the painter must recognize this screen:\n#{screen}"
      strip_ansi(painted).each_line do |line|
        assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                         "#{verb}: painted row over 115 display columns: #{line.inspect}"
      end
    end
  end

  # --- W1-W5e: the field-table fitter's own invariants -------------------------------------

  def test_label_cell_never_truncates
    long_label = "VeryLongLabelWord" * 5
    rows = [
      "| | | |",
      "| --- | --- | --- |",
      "| **#{long_label}** | short value | short note |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 40)
    assert_includes fitted, "**#{long_label}**",
                     "the label column must keep its natural width and never truncate"
  end

  def test_separator_row_never_truncates
    rows = [
      "| | | |",
      "| --- | --- | --- |",
      "| **Key** | #{'v' * 300} | #{'n' * 300} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 40)
    lines = fitted.lines.map(&:chomp)
    assert_equal "| | | |", lines[0]
    assert_equal "| --- | --- | --- |", lines[1]
  end

  def test_value_shrinks_before_note
    rows = [
      "| | | |",
      "| --- | --- | --- |",
      "| **K** | #{'V' * 60} | #{'N' * 15} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 60)
    cells = ScreenPaint.cells_of(fitted.lines.map(&:chomp)[2])
    assert_equal "N" * 15, cells[2],
                 "a note that already fits must never be touched while the value still has room to shrink"
    assert cells[1].end_with?("…"), "the value, not the note, must be the one that shrinks"
    assert_operator cells[1].length, :<=, 30
  end

  def test_note_drops_whole_when_it_cannot_fit
    rows = [
      "| | | |",
      "| --- | --- | --- |",
      "| **K** | #{'V' * 100} | #{'N' * 40} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 40)
    cells = ScreenPaint.cells_of(fitted.lines.map(&:chomp)[2])
    assert_equal "", cells[2], "a note with under 8 columns left must be dropped whole, never squeezed to \"in…\""
    assert cells[1].end_with?("…")
  end

  def test_value_floor_holds
    rows = [
      "| | |",
      "| --- | --- |",
      "| **K** | #{'V' * 200} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 20)
    cells = ScreenPaint.cells_of(fitted.lines.map(&:chomp)[2])
    assert_operator ScreenPaint.display_columns(cells[1]), :>=, 24,
                     "the value column must never shrink below its 24-column floor, even under extreme pressure"
  end

  def test_bar_cell_is_never_truncated
    bar = ("█" * 20) + " 5 / 10"
    rows = [
      "| | |",
      "| --- | --- |",
      "| **Progress** | #{bar} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 20)
    cells = ScreenPaint.cells_of(fitted.lines.map(&:chomp)[2])
    assert_equal bar, cells[1], "a progress bar cell must never be truncated, mid-run or otherwise"
  end

  def test_display_columns_counts_wide_glyphs_as_two
    assert_equal 5, ScreenPaint.display_columns("abcde")
    assert_equal 10, ScreenPaint.display_columns("█" * 5)
    assert_equal 0, ScreenPaint.display_columns("")
    assert_equal 3, ScreenPaint.display_columns("\e[1mabc\e[0m")
  end

  def test_truncation_reserves_the_ellipsis_display_width
    text = "a" * 20
    result = ScreenPaint.truncate_on_word_boundary(text, 10)
    assert_operator ScreenPaint.display_columns(result), :<=, 10
  end

  def test_backstop_does_not_double_ellipsize
    row = "#{'a' * 10}… |"
    result = ScreenPaint.truncate_on_word_boundary(row, 12)
    assert_equal 1, result.scan("…").length,
                 "a slice that already ends in an ellipsis must not gain a second one: #{result.inspect}"
  end

  def test_two_column_field_table_fits
    rows = [
      "| | |",
      "| --- | --- |",
      "| **Key** | #{'v' * 300} |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 50)
    fitted.each_line { |l| assert_operator ScreenPaint.display_columns(l.chomp), :<=, 50 }
    assert_includes fitted, "**Key**"
  end

  # Post-execution review, P1: `fit_field_table_block` spent width/budget arithmetic in
  # characters against the 115 DISPLAY-column bound - a bar row's glyphs (2 columns each) plus
  # a long note in the SAME row renders 134 columns while every width in the arithmetic reads
  # under 115. The exact repro from the review.
  def test_bar_row_with_a_long_note_fits
    bar = ("█" * 11) + ("░" * 9)
    text = "| | | |\n| --- | --- | --- |\n| **Progress** | #{bar} 4 / 7 | #{'note ' * 22}|\n"
    fitted = ReportScreen.fit_screen(text)
    fitted.each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "a field row with a progress bar AND a long note must still fit: #{line.inspect}"
    end
  end

  # Post-execution review, P5: `fit_field_table_block` dropped the re-pad `fit_table_block`'s
  # own `padded_column` rule already does, so a fitted field table prints unaligned where an
  # unfitted (or alpha-shipped) one prints its label column ljust-padded to the widest label.
  def test_fitted_field_table_keeps_its_padding
    rows = [
      "| | | |",
      "| --- | --- | --- |",
      "| **Stage**    | value one | #{'n' * 200} |",
      "| **Progress** | value two | short |",
    ]
    fitted = ReportScreen.fit_field_table_block(rows, 60)
    lines = fitted.lines.map(&:chomp)
    # ScreenPaint.cells_of strips each cell, which would hide the very padding under test -
    # ReportScreen.raw_cells_of keeps it, exactly like fit_table_block's own padded_column rule.
    label1 = ReportScreen.raw_cells_of(lines[2])[0]
    label2 = ReportScreen.raw_cells_of(lines[3])[0]
    assert_equal label2.length, label1.length,
                 "a fitted field table must keep its rows' label column ljust-aligned, like an unfitted one"
  end

  # --- W7-W7b: the painter/plain data-table shrink minimums --------------------------------

  def test_shrink_picks_widest_text_column
    block = [
      "| Id | Detail | Status |",
      "| --- | --- | --- |",
      "| 1234567890 | #{'D' * 100} | open |",
    ]
    fitted = ReportScreen.fit_table_block(block, 32)
    cells = ScreenPaint.cells_of(fitted.lines.map(&:chomp).last)
    assert_equal "1234567890", cells[0],
                 "a 10-column id column must keep its own natural width, never shrink for the widest TEXT column"
    assert_operator cells[1].length, :<, 100, "the widest text column must be the one that shrinks"
    assert_equal "open", cells[2]
  end

  def test_bold_header_data_table_is_not_a_field_table
    rows = [
      "| **Kind** | Detail |",
      "| --- | --- |",
      "| suite | some real detail here |",
    ]
    refute ScreenPaint.field_table?(rows),
           "a data table must not be misclassified just because its header cell is bold"
  end

  def test_unshrinkable_data_table_is_still_bounded
    cols = 20
    header = "| " + (1..cols).map { |i| "Column#{i}" }.join(" | ") + " |"
    sep = "| " + (["---"] * cols).join(" | ") + " |"
    row = "| " + (["XXXXXXXXXXXXXXXXXXXX"] * cols).join(" | ") + " |"
    fitted = ReportScreen.fit_screen("#{header}\n#{sep}\n#{row}\n")
    fitted.each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "an unshrinkable data table must still be bounded by the row backstop"
    end
  end

  # Post-execution review, P2/P3: `paint_data_table`/`fit_table_block` credited overage only to
  # columns flagged as bar columns, so a padded cell carrying an ellipsis (added upstream by
  # ReportScreen.fit_row_cell, exactly as roadmap_state_entries_table does for the Intent
  # column) or a bar was never paid for - the live 116-column `roadmap state`/`dashboard`
  # rows.
  def test_padded_cell_overage_is_charged_to_the_budget
    # The live shape: ReportScreen.fit_row_cell already truncated the Intent cell to an
    # ellipsis before paint_data_table ever sees it; padding that cell to the column's shared
    # width (across every row) must charge the ellipsis's own display overage against the
    # budget, or the row lands one column over once painted.
    intent = ("A" * 89) + "…"
    rows = [
      "| Batch | Intent | Lead |",
      "| --- | --- | --- |",
      "| Batch 3 | #{intent} | agent-name-here-longer · abcd1234 |",
      "| Batch 1 | Short intent title | idle |",
    ]
    painted = ScreenPaint.paint_table(rows, color: false, width: 115, markdown_safe: false)
    painted.each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "a painted row with a padded ellipsis cell must stay within 115: #{line.inspect}"
    end
  end

  # Post-execution review, P4: `paint_data_table` had no row-level backstop at all, so a table
  # whose columns are all pinned at their floor (the painted twin of
  # test_unshrinkable_data_table_is_still_bounded) rendered straight past 115.
  def test_painted_data_table_is_backstopped
    cols = 20
    header = "| " + (1..cols).map { |i| "Column#{i}" }.join(" | ") + " |"
    sep = "| " + (["---"] * cols).join(" | ") + " |"
    row = "| " + (["XXXXXXXXXXXXXXXXXXXX"] * cols).join(" | ") + " |"
    painted = ScreenPaint.paint_table([header, sep, row], color: true, width: 115, markdown_safe: false)
    painted.each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "a painted data table must be bounded even when every column sits at its floor"
    end
  end

  # Post-execution review, D: the fixture must actually reproduce what the live store does -
  # a Batches table with at least ten rows and heterogeneous Status/Lead lengths (never a
  # single repeated width, which would hide a partial-credit overage bug), plus its own bar
  # row with a long note.
  def test_wide_fixture_matches_the_live_store_shape
    lines = build_all_screens["roadmap state"].lines
    header_idx = lines.index { |l| l.include?("Graph ID") && l.include?("Intent") && l.include?("Status") }
    refute_nil header_idx, "roadmap state must carry the Batches table header"

    block = []
    i = header_idx
    while i < lines.length && lines[i].lstrip.start_with?("|")
      block << lines[i].chomp
      i += 1
    end
    data_rows = block.reject { |l| l.match?(ScreenPaint::SEPARATOR_RE) }[1..].to_a

    assert_operator data_rows.length, :>=, 10, "the Batches table needs at least ten intent rows"
    statuses = data_rows.map { |r| ScreenPaint.cells_of(r)[3] }
    leads = data_rows.map { |r| ScreenPaint.cells_of(r)[5] }
    assert_operator statuses.uniq.length, :>=, 3, "Status lengths must be heterogeneous, like the live store"
    assert_operator leads.uniq.length, :>=, 3, "Lead lengths must be heterogeneous, like the live store"

    bar = ("█" * 11) + ("░" * 9)
    bar_and_note = "| | | |\n| --- | --- | --- |\n| **Progress** | #{bar} 4 / 7 | #{'note ' * 22}|\n"
    ReportScreen.fit_screen(bar_and_note).each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "the fixture's own bar+long-note row must fit, matching the live store repro"
    end
  end

  # --- 331f1a: separator rows on the data-table path --------------------------------
  #
  # The measured root cause (ACTION_1): `fit_table_block`'s data-table branch rebuilt
  # every separator row from the SHRUNK widths (with a `[w, 3].max` floor), so it
  # assembled wider than any data row and was the only row that ever tripped the
  # unconditional row backstop (F28), landing as a cut fragment - or, when the rebuilt
  # form happened to still fit under 115, as a row wider than its own "---" input
  # (WIDENED, not byte-identical either). The lead ruling: a separator passes through
  # byte-identical whenever its OWN unfitted input already fits the 115 bound; only
  # when even that unmodified input cannot fit does the backstop apply to it - so the
  # exemption never reopens test_fit_screen_backstops_an_unshrinkable_row (above) or
  # test_unshrinkable_data_table_is_still_bounded, both of which build a 20-column
  # table whose minimal separator (6n+1 = 121 characters) already exceeds 115 on its
  # own, unfitted.

  # X3: the fix must not let a DATA row (as opposed to the separator) slip past 115 -
  # a regression guard on the same three-column, 1/4/6-header shape X1/X2 use.
  def test_data_rows_still_fit
    header = "| N | Need | Reason |"
    sep = "| --- | --- | --- |"
    row = "| N1 | Do the thing | #{'W' * 260} |"
    fitted = ReportScreen.fit_screen("#{header}\n#{sep}\n#{row}\n")
    fitted.each_line do |line|
      next if line.chomp.match?(ScreenPaint::SEPARATOR_RE)
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "a data row must stay within 115 after the separator fix: #{line.inspect}"
    end
  end

  # X5: a table whose minimal separator ("| --- | ... |") ITSELF already exceeds 115
  # before any shrink must still be backstopped, never exempted just because it is a
  # separator - the bound wins where the two rules cannot both hold. Unlike the two
  # protected tests above, the data row here is short, isolating the separator's own
  # unconditional-exemption risk from the "widest row" mechanics those two exercise.
  def test_separator_wider_than_the_bound_is_still_backstopped
    cols = 20
    header = "| " + (1..cols).map { |i| "H#{i}" }.join(" | ") + " |"
    sep = "| " + (["---"] * cols).join(" | ") + " |"
    row = "| " + (["short"] * cols).join(" | ") + " |"
    fitted = ReportScreen.fit_screen("#{header}\n#{sep}\n#{row}\n")
    lines = fitted.lines
    assert_equal 3, lines.length, "the fixture's three rows must not wrap into more lines"
    # Found by position, not by SEPARATOR_RE: a row the backstop truncates ends in an
    # ellipsis, which SEPARATOR_RE (correctly) no longer recognizes as a separator.
    sep_line = lines[1]
    assert_operator ScreenPaint.display_columns(sep_line.chomp), :<=, 115,
                     "a separator whose minimal form itself exceeds 115 must still be backstopped"
  end

  # X6: the WIDENED failure shape - not cut, but rebuilt wider than its own input,
  # which D1 forbids just as much as a cut. This asserts byte-identity against the
  # UNFITTED separator, which a mere "not truncated" check would miss. The shape:
  # a three-column table (mirroring the live session Evidence table's Kind/Detail/
  # Source order) where every column's natural width is already >= 3, so the old
  # `[w, 3].max` floor never inflates any column - the rebuilt separator lands
  # exactly at the 115 budget, comfortably under the bound and so never backstopped,
  # yet still not the original "---" the input actually wrote.
  def test_session_separators_are_byte_identical
    header = "| Kind | Detail | Source |"
    sep = "| --- | --- | --- |"
    row = "| ship | #{'D' * 150} | outcome.md |"
    fitted = ReportScreen.fit_screen("#{header}\n#{sep}\n#{row}\n")
    sep_line = fitted.lines.find { |l| l.chomp.match?(ScreenPaint::SEPARATOR_RE) }
    refute_nil sep_line
    assert_equal sep, sep_line.chomp,
                 "a separator that already fits must render byte-identical to its input, not rebuilt wider"
  end

  # X7: a blank `| | | |` scaffold row reaching the data-table branch (ScreenPaint.
  # field_table? routes every shipped scaffold to the field-table branch first, so this
  # is a documented edge, not a live defect) must also pass through unchanged rather
  # than being rewritten as a dashed rule - the same fitting-input-already-fits rule
  # that fixes the separator applies to it, since `is_sep` classifies it identically.
  def test_blank_scaffold_row_passes_through
    header = "| N | Need | Reason |"
    blank = "| | | |"
    row = "| N1 | Do the thing | #{'W' * 260} |"
    fitted = ReportScreen.fit_table_block([header, blank, row], 115)
    lines = fitted.lines.map(&:chomp)
    assert_includes lines, blank,
                     "a blank scaffold row reaching the data-table branch must pass through unchanged"
  end
end
