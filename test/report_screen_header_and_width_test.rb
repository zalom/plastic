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

# Intent 331f (D5/D6/D7): the column-vocabulary and width-bound sweep across the report-screen
# family - F19-F22, F25-F28. Owner ruling 2026-09-05 11:05 UTC: "What" is never a column name;
# the id column reads "Graph ID", the title column reads "Intent"; no rendered row passes 115
# visible columns.
class ReportScreenHeaderAndWidthTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @home = Dir.mktmpdir("report-screen-header-width")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def tier_root
    root = File.join(@home, "projects", "demo")
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, id:, title:, section: "Active")
    File.write(File.join(root, "INDEX.md"), <<~MD)
      # Index

      ## #{section}
      - [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md)

      ## Future

      ## Completed

      ## Abandoned
    MD
  end

  def make_intent(root, id:, title:, checklist:, savepoint:, action_body: nil, outcome_body: nil)
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
    MD
    File.write(File.join(dir, "checklist.md"), checklist)
    File.write(File.join(dir, "savepoint.md"), savepoint)
    File.write(File.join(dir, "actions", "ACTION_1.md"), action_body) if action_body
    File.write(File.join(dir, "outcome.md"), outcome_body) if outcome_body
    dir
  end

  def checklist_with(total:, done:)
    items = (1..total).map { |n| "- [#{n <= done ? 'x' : ' '}] S#{n} step #{n}" }
    "# Checklist\n\n#{items.join("\n")}\n"
  end

  HOW_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze
  DONE_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T13:51:42Z  Done  delivered\n".freeze

  # Every header this sweep must never see again.
  FORBIDDEN_WHAT_HEADER_RE = /\|\s*What\s*\|/.freeze

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  # --- F19/F20: no screen carries a "What" header; the id column reads "Graph ID" -----------

  def test_no_screen_carries_a_what_header
    root = tier_root
    write_index(root, id: "12", title: "Demo intent")
    dir = make_intent(root, id: "12", title: "Demo intent",
                       checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER,
                       action_body: "### S1 - proof\n\n| Row | Op | Failure | Test |\n| --- | --- | --- | --- |\n| 1 | x | y | z |\n")

    intent_screen = IntentScreen.render(intent_dir: dir, store_root: root,
                                         template: File.read(File.join(REPO, "templates", "intent-screen.md")))
    state_screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: nil,
                                              template: File.read(File.join(REPO, "templates", "report-state.md")))
    plan_screen = ReportScreen.render_plan(intent_dir: dir, store_root: root,
                                            template: File.read(File.join(REPO, "templates", "report-plan.md")))
    roster_screen = ReportScreen.render_roster(root)

    # Post-exec review finding 2: this sweep claimed "every verb" but only ever rendered four
    # of them. A second, delivered intent gives delivered/delay/session something real to
    # render, and a roadmap fixture built on the same store gives the three roadmap verbs the
    # same chance to leak a "What" header.
    delivered_dir = make_intent(root, id: "19", title: "Demo delivered",
                                 checklist: checklist_with(total: 1, done: 1), savepoint: DONE_LEDGER,
                                 outcome_body: <<~MD)
                                   ---
                                   disposition: delivered
                                   ---
                                   # Outcome

                                   ## Delivered
                                   | Row | What |
                                   | --- | --- |
                                   | S1 | shipped it |

                                   ## Needs you
                                   | N | What | Why |
                                   | --- | --- | --- |
                                   | N1 | pick a seam | waits on owner |
                                 MD
    delivered_screen = ReportScreen.render_delivered(intent_dir: delivered_dir)
    delay_screen = ReportScreen.render_delay(intent_dir: delivered_dir)
    session_screen = ReportScreen.render_session(dirs: [delivered_dir], skipped: 0, store_root: root)

    roadmaps_dir = File.join(root, "roadmaps")
    FileUtils.mkdir_p(roadmaps_dir)
    roadmap_path = File.join(roadmaps_dir, "demo.md")
    File.write(roadmap_path, <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 19 Demo delivered - delivered
      ## Log
      - 2026-07-10 02:55 UTC roadmap closed.
    MD
    roadmap_plan = ReportScreen.render_roadmap(path: roadmap_path, verb: "plan", store_root: root)
    roadmap_state = ReportScreen.render_roadmap(path: roadmap_path, verb: "state", store_root: root)
    roadmap_delivered = ReportScreen.render_roadmap(path: roadmap_path, verb: "delivered", store_root: root)

    [intent_screen, state_screen, plan_screen, roster_screen, delivered_screen, delay_screen,
     session_screen, roadmap_plan, roadmap_state, roadmap_delivered].each do |screen|
      refute_match(FORBIDDEN_WHAT_HEADER_RE, screen, "a screen still carries a What header:\n#{screen}")
    end

    assert_includes intent_screen, "| Step | Status | Detail |"
    assert_includes state_screen, "| Step | Status | Detail |"
    assert_includes plan_screen, "| Step | Action | Detail |"
    assert_includes roster_screen, "| Graph ID | Stage | Progress | Changed | Lead |"
  end

  # --- F21: the plan screen's Asked row is the intent title before its first colon ---------

  def test_plan_asked_is_title_before_colon
    root = tier_root
    title = "Skills bound to reports: every skill that shows state names its report verb"
    write_index(root, id: "13", title: "Skills bound to reports")
    dir = make_intent(root, id: "13", title: title, checklist: checklist_with(total: 1, done: 0),
                       savepoint: HOW_LEDGER)

    plan_screen = ReportScreen.render_plan(intent_dir: dir, store_root: root,
                                            template: File.read(File.join(REPO, "templates", "report-plan.md")))
    asked_line = plan_screen.lines.find { |l| l.start_with?("| **Asked**") }
    refute_nil asked_line
    assert_includes asked_line, "Skills bound to reports"
    refute_includes asked_line, "every skill that shows state names"

    # A short ask with no colon at all renders unchanged (nothing to split on).
    assert_equal "Skills bound to reports",
                 ReportScreen.plan_asked_title(dir)
  end

  def test_plan_asked_title_with_no_colon_is_unchanged
    root = tier_root
    write_index(root, id: "14", title: "Short ask")
    dir = make_intent(root, id: "14", title: "Short ask, no colon here at all",
                       checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    assert_equal "Short ask, no colon here at all", ReportScreen.plan_asked_title(dir)
  end

  # --- F22: the painter recognizes the renamed headers -------------------------------------

  def test_painter_recognizes_renamed_headers
    screen = "## ▶ 12 · Demo · delivered\n" \
             "2026-08-30 12:00 UTC · auto · 1 min · not recorded\n\n" \
             "**Delivered**\n| Row | Detail | Proven by |\n| --- | --- | --- |\n| S1 | a thing | 1 test |\n\n" \
             "**Needs you**\n| N | Need | Reason |\n| --- | --- | --- |\n| N1 | pick a seam | waits on owner |\n"
    painted = ScreenPaint.paint(screen)
    refute_nil painted, "the painter must still recognize a screen with the renamed headers"
    plain = painted.gsub(/\e\[[0-9;]*m/, "")
    assert_includes plain, "Row"
    assert_includes plain, "Detail"
    assert_includes plain, "Need"
    assert_includes plain, "Reason"
    refute_match(/^\s*\|/, plain)

    # Post-exec review finding 4: a hand-typed fixture only proves the painter recognizes a
    # header shape someone wrote by hand for the test. Paint the SAME renamed headers through
    # a real render_delivered and render_state call, sourced from files on disk, so the
    # header-driven kind detection is proven against what the renderers actually emit.
    root = tier_root
    write_index(root, id: "22", title: "Painter real render demo")
    dir = make_intent(root, id: "22", title: "Painter real render demo",
                       checklist: checklist_with(total: 1, done: 0), savepoint: DONE_LEDGER,
                       outcome_body: <<~MD)
                         ---
                         disposition: delivered
                         ---
                         # Outcome

                         ## Delivered
                         | Row | What |
                         | --- | --- |
                         | S1 | shipped it |

                         ## Needs you
                         | N | What | Why |
                         | --- | --- | --- |
                         | N1 | pick a seam | waits on owner |
                       MD

    real_delivered = ReportScreen.render_delivered(intent_dir: dir)
    painted_delivered = ScreenPaint.paint(real_delivered, color: true)
    refute_nil painted_delivered, "the painter must recognize a real render_delivered screen"
    plain_delivered = painted_delivered.gsub(/\e\[[0-9;]*m/, "")
    assert_includes plain_delivered, "Detail"
    assert_includes plain_delivered, "Need"
    assert_includes plain_delivered, "Reason"

    real_state = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: nil,
                                            template: File.read(File.join(REPO, "templates", "report-state.md")))
    painted_state = ScreenPaint.paint(real_state, color: true)
    refute_nil painted_state, "the painter must recognize a real render_state screen"
    plain_state = painted_state.gsub(/\e\[[0-9;]*m/, "")
    assert_includes plain_state, "Detail"
  end

  # --- F25: lead_cell is one freshness rule for every screen --------------------------------

  def test_lead_cells_share_one_freshness_rule
    root = tier_root
    dir = make_intent(root, id: "15", title: "Lead demo", checklist: checklist_with(total: 1, done: 0),
                       savepoint: HOW_LEDGER)
    now = Time.utc(2026, 9, 5, 12, 0, 0)

    # No lock at all: idle.
    assert_equal "idle", ReportScreen.lead_cell(dir, now: now)

    # A fresh lock: "agent · key".
    Lock.acquire(dir, session: "abcdef1234567890", harness: "claude", agent: "plastic-enforcer", now: now)
    lock_path = File.join(dir, "delivery.lock")
    File.utime(now, now, lock_path)
    assert_equal "plastic-enforcer · abcdef12", ReportScreen.lead_cell(dir, now: now)

    # An older heartbeat, past the TTL: "stale · N min", never a bare idle and never the
    # session key.
    stale_now = now + Lock::TTL_SECONDS + (45 * 60)
    result = ReportScreen.lead_cell(dir, now: stale_now)
    assert_equal "stale · 75 min", result
    refute_includes result, "abcdef12"

    # An unreadable lock: idle.
    File.write(File.join(dir, "delivery.lock"), "not json")
    assert_equal "idle", ReportScreen.lead_cell(dir, now: now)
  end

  # --- header renames pinned against real rendered output (post-exec review finding 3) -------

  def test_plan_risks_header_renders_from_real_plan_md
    root = tier_root
    write_index(root, id: "20", title: "Risk demo")
    dir = make_intent(root, id: "20", title: "Risk demo", checklist: checklist_with(total: 1, done: 0),
                       savepoint: HOW_LEDGER)
    File.write(File.join(dir, "plan.md"), <<~MD)
      # Plan

      ## Risks
      - the migration might run twice
    MD

    plan_screen = ReportScreen.render_plan(intent_dir: dir, store_root: root,
                                            template: File.read(File.join(REPO, "templates", "report-plan.md")))
    assert_includes plan_screen, "| N | Risk |"
  end

  def test_roadmap_log_and_delivered_headers_render_from_real_roadmap_md
    root = tier_root
    write_index(root, id: "21", title: "Roadmap demo entry", section: "Completed")

    roadmaps_dir = File.join(root, "roadmaps")
    FileUtils.mkdir_p(roadmaps_dir)
    roadmap_path = File.join(roadmaps_dir, "demo.md")
    File.write(roadmap_path, <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 21 Roadmap demo entry - delivered
      ## Log
      - 2026-07-10 02:55 UTC roadmap closed.
    MD

    delivered = ReportScreen.render_roadmap(path: roadmap_path, verb: "delivered", store_root: root)
    assert_includes delivered, "| Batch | Graph ID | Intent | Merged |"
    assert_includes delivered, "| When | Event | Detail |"
  end

  # --- F26: no rendered row passes 115 visible columns --------------------------------------

  def test_no_screen_row_passes_115_columns
    root = tier_root
    # Word-separated, not a single unbroken run: a title with no whitespace at all pushes
    # ReportScreen.truncate_on_word_boundary back to the last (very early) space it can find,
    # which can mangle the opener's own " · " grammar - a real intent title always carries
    # spaces, so this keeps the fixture realistic while still forcing truncation.
    long_goal = (["Goal"] * 60).join(" ")
    write_index(root, id: "16", title: long_goal)
    dir = make_intent(root, id: "16", title: long_goal, checklist: checklist_with(total: 1, done: 0),
                       savepoint: HOW_LEDGER,
                       outcome_body: <<~MD)
                         ---
                         disposition: delivered
                         ---
                         # Outcome

                         ## Delivered
                         | Row | What |
                         | --- | --- |
                         | S1 | #{"D" * 300} |

                         ## Verification
                         - suite green

                         ## Needs you
                         | N | What | Why |
                         | --- | --- | --- |
                         | N1 | #{"D" * 80} | #{"x" * 10} |
                         | N2 | #{"x" * 10} | #{"D" * 80} |
                       MD
    File.write(File.join(dir, "savepoint.md"), DONE_LEDGER)

    state_screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: nil,
                                              template: File.read(File.join(REPO, "templates", "report-state.md")))
    delivered_screen = ReportScreen.render_delivered(intent_dir: dir)
    roster_screen = ReportScreen.render_roster(root)

    # Post-exec review finding 1: the painter is a rendered path too, and D7 binds every
    # RENDERED row, not only the plain markdown fit_screen already bounds. The Needs-you rows
    # above are the reproduction - a different row is the longest in each column (N1's Need
    # cell 80 chars against a 10-char Why, N2 the other way round), which the plain markdown
    # table already bounds correctly (each row un-padded, so its own length carries), but a
    # painter that pads every cell to the widest value ACROSS ALL ROWS can paint a row wider
    # than 115 even though the plain row it started from never was.
    [state_screen, delivered_screen, roster_screen].each do |screen|
      screen.each_line do |line|
        assert_operator line.chomp.length, :<=, 115, "row over 115 columns: #{line.inspect}"
      end

      painted = ScreenPaint.paint(screen, color: true)
      refute_nil painted, "the painter must recognize this screen:\n#{screen}"
      strip_ansi(painted).each_line do |line|
        assert_operator line.chomp.length, :<=, 115, "painted row over 115 columns: #{line.inspect}"
      end
    end
  end

  def test_fit_screen_leaves_a_fitting_screen_byte_identical
    text = "## ▶ 12 · Demo\n\n| Step | Status | Detail |\n| --- | --- | --- |\n| S1 | open | short |\n"
    assert_equal text, ReportScreen.fit_screen(text)
  end

  # --- F27: the fitter splits cells exactly as the painter does ------------------------------

  def test_fit_screen_splits_cells_like_the_painter
    row = "| a \\| b | #{'x' * 200} |"
    header = "| Kind | #{'H' * 200} |"
    sep = "| --- | --- |"
    text = "#{header}\n#{sep}\n#{row}\n"
    fitted = ReportScreen.fit_screen(text)
    fitted.lines.each do |line|
      next unless line.lstrip.start_with?("|")
      assert_equal ScreenPaint.cells_of(line.chomp).length, ReportScreen.raw_cells_of(line.chomp).length
    end
  end

  # --- F28: the backstop truncates the assembled row when every column is at its floor ------

  def test_fit_screen_backstops_an_unshrinkable_row
    cols = 20
    header = "| " + (1..cols).map { |i| "C#{i}" }.join(" | ") + " |"
    sep = "| " + (["---"] * cols).join(" | ") + " |"
    row = "| " + (["XXXXXXXXXXXXXXXXXXXX"] * cols).join(" | ") + " |"
    text = "#{header}\n#{sep}\n#{row}\n"

    fitted = ReportScreen.fit_screen(text)
    fitted.lines.each do |line|
      assert_operator line.chomp.length, :<=, 115, "backstop failed to bound: #{line.inspect}"
    end
  end

  # --- D8 (orchestrator ruling, 2026-09-05): where a title actually ends -------
  #
  # The title ends at the first colon FOLLOWED BY A SPACE, so a URL or a clock time inside a
  # title survives. With no such colon the title is its first sentence, and with no sentence
  # either it is the whole line. The live case is zlatkocodes intent 4, whose line opens
  # "About page redesign and header navigation order. Rebuild https://zlatkocodes.com/about/
  # (src/about.md) in the current template styling: ..." - splitting on any colon cuts it at
  # "https" and names nothing a reader recognizes.

  ZLATKOCODES_4 = "About page redesign and header navigation order. Rebuild " \
                  "https://zlatkocodes.com/about/ (src/about.md) in the current template " \
                  "styling: centered circular photo of the owner"

  def test_title_ends_at_a_colon_followed_by_a_space # D8.1
    assert_equal "Skills bound to reports",
                 ReportScreen.title_before_colon("Skills bound to reports: every skill that shows state")
  end

  def test_a_colon_inside_a_url_does_not_end_the_title # D8.2
    title = ReportScreen.title_before_colon(ZLATKOCODES_4)
    assert_equal "About page redesign and header navigation order.", title
    refute_includes title, "https", "a colon inside a URL must not end the title"
  end

  def test_a_colon_inside_a_clock_time_does_not_end_the_title # D8.3
    assert_equal "Capture the boot banner at 06:55Z and diff it",
                 ReportScreen.title_before_colon("Capture the boot banner at 06:55Z and diff it")
  end

  def test_a_title_with_no_qualifying_colon_falls_back_to_its_first_sentence # D8.4
    assert_equal "One sentence stands alone.",
                 ReportScreen.title_before_colon("One sentence stands alone. A second one follows it.")
  end

  def test_a_title_with_neither_colon_nor_sentence_is_the_whole_line # D8.5
    assert_equal "A bare title with nothing to split on",
                 ReportScreen.title_before_colon("A bare title with nothing to split on")
  end

  def test_a_title_opening_with_its_colon_still_names_something # D8.6
    refute_empty ReportScreen.title_before_colon(": opens with its colon")
    assert_includes ReportScreen.title_before_colon(": opens with its colon"), "opens with its colon"
  end

  def test_the_dashboard_reads_titles_through_the_one_helper # D8.7
    source = File.read(File.expand_path("../scripts/dashboard.rb", __dir__))
    body = source[/def screen_intent_title.*?\nend/m]
    refute_nil body, "screen_intent_title is gone; the assertion needs rewriting"
    assert_includes body, "ReportScreen.title_before_colon",
                    "the dashboard must read titles through the one helper, not a second split"
    refute_match(/split\(":"/, body, "a second colon rule lives in dashboard.rb")
  end
end
