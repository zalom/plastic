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
    screens
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
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
    label1 = ScreenPaint.cells_of(lines[2])[0]
    label2 = ScreenPaint.cells_of(lines[3])[0]
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
    bar = ("█" * 40) + ("░" * 10)
    rows = [
      "| Id | Detail | Note |",
      "| --- | --- | --- |",
      "| 1 | #{bar} | short note here |",
      "| 2 | #{'D' * 60} | #{'n' * 60} |",
    ]
    painted = ScreenPaint.paint_table(rows, color: false, width: 115, markdown_safe: false)
    painted.each_line do |line|
      assert_operator ScreenPaint.display_columns(line.chomp), :<=, 115,
                       "a painted row with a padded bar/ellipsis cell must stay within 115: #{line.inspect}"
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
end
