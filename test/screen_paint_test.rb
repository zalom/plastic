require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/screen_paint"

# Intent 317a, S10 (D1): ScreenPaint parses the emitted plain screens - the
# only shapes our own renderers produce - and re-lays them out in the shipped
# intent-screen ANSI vocabulary. Content-survival is the acceptance (A5):
# every field value and note survives, no pipe or separator row survives, and
# unparseable text returns nil so callers fail open to plain.
class ScreenPaintTest < Minitest::Test
  ESC = "\e".freeze
  A = IntentScreenAnsi

  def setup
    @root = Dir.mktmpdir("screen-paint")
    @store = File.join(@root, "store")
    @dir = File.join(@store, "21--paint")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    File.write(File.join(@dir, "21--paint.md"), <<~MD)
      ---
      id: "21"
      intent: "Paint demo"
      sources: []
      chain: []
      created: 2026-08-31
      author: human
      tags: []
      ---

      ## Intent
      Paint demo

      ## Context
      ctx

      ## Insights
      2026-08-31T10:00:00Z · Exec · tester (autonomous) — One durable nugget. With a tail.
    MD
    File.write(File.join(@dir, "checklist.md"),
               "# Checklist\n\n- [x] S1 - first step done\n- [ ] S2 - second step open\n")
    File.write(File.join(@dir, "savepoint.md"),
               "2026-08-31T09:00:00Z  What  21--paint.md\n2026-08-31T10:00:00Z  Exec  started\n")
    File.write(File.join(@dir, "outcome.md"), <<~MD)
      ---
      disposition: delivered
      mode: auto
      ---
      # Outcome: Paint demo

      ## Summary
      shipped

      ## Delivered
      | Row | What |
      | --- | --- |
      | S1 | the painted thing |

      ## Verification
      - suite: 10 runs, 20 assertions, 0 failures

      ## Needs you
      None

      ## Follow-ups
      None
    MD
    File.write(File.join(@dir, "actions", "ACTION_1.md"),
               "# ACTION_1\n\n### S1 - first\n| Row | Failure | Test |\n| --- | --- | --- |\n| S1a | breaks | test |\n")
    File.write(File.join(@root, "INDEX.md"),
               "# INDEX\n\n## Active\n- [21 - Paint demo](store/21--paint/21--paint.md) - demo\n\n## Completed\n")
    @state_template = File.read(File.expand_path("../templates/report-state.md", __dir__))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def strip_ansi(text)
    text.gsub(/\e\[[0-9;]*m/, "")
  end

  def state_screen
    ReportScreen.render_state(intent_dir: @dir, store_root: @root,
                              changed: "test print", template: @state_template)
  end

  # --- content survival on the state screen (matrix S10a/S10b) ---

  def test_state_screen_paints_with_every_value_surviving_and_no_pipes
    painted = ScreenPaint.paint(state_screen, color: true)
    refute_nil painted
    assert_includes painted, ESC
    plain = strip_ansi(painted)
    ["21", "Paint demo", "Active", "test print",
     "the reason this screen printed", "first step done", "second step open"].each do |v|
      assert_includes plain, v
    end
    refute_match(/^\s*\|/, plain)
    refute_includes plain, "---"
    refute_includes plain, "**"
  end

  def test_state_screen_paint_colors_done_and_open_badges
    painted = ScreenPaint.paint(state_screen, color: true)
    assert_match(/\e\[[0-9;]*mdone/, painted)
    assert_match(/\e\[[0-9;]*mopen/, painted)
  end

  # --- the other three report screens plus the intent screen (S10d) ---

  def test_delivered_screen_paints
    out = ReportScreen.render_delivered(intent_dir: @dir)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    plain = strip_ansi(painted)
    ["delivered", "the painted thing", "auto", "Needs you", "None"].each { |v| assert_includes plain, v }
    refute_match(/^\s*\|/, plain)
  end

  def test_delay_screen_paints
    out = ReportScreen.render_delay(intent_dir: @dir)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    assert_includes strip_ansi(painted), "Where the time went"
  end

  def test_roster_screen_paints
    out = ReportScreen.render_roster(@root, changed: nil)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    plain = strip_ansi(painted)
    assert_includes plain, "In delivery"
    assert_includes plain, "21"
    refute_match(/^\s*\|/, plain)
  end

  def test_intent_screen_paints
    template = File.read(File.expand_path("../templates/intent-screen.md", __dir__))
    out = IntentScreen.render(intent_dir: @dir, store_root: @root, template: template)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    assert_includes strip_ansi(painted), "Paint demo"
  end

  # --- fail open (S10c) and color off ---

  def test_garbage_returns_nil
    assert_nil ScreenPaint.paint("just some prose\nwith lines\n", color: true)
    assert_nil ScreenPaint.paint("# A heading\n\nprose\n", color: true)
    assert_nil ScreenPaint.paint("", color: true)
  end

  def test_color_false_lays_out_without_escapes
    painted = ScreenPaint.paint(state_screen, color: false)
    refute_nil painted
    refute_includes painted, ESC
    refute_match(/^\s*\|/, painted)
  end

  # --- markdown_safe (S10e) ---

  def test_markdown_safe_strips_backticks
    File.write(File.join(@dir, "checklist.md"),
               "# Checklist\n\n- [ ] S1 - touch `scripts/lib/lock.rb` carefully\n")
    painted = ScreenPaint.paint(state_screen, color: true, markdown_safe: true)
    plain = strip_ansi(painted)
    assert_includes plain, "scripts/lib/lock.rb"
    refute_includes plain, "`"
  end

  # --- the message region walker (S12's grammar home, B10) ---

  def test_region_end_stops_before_trailing_prose
    message = "#{ReportScreen.render_delivered(intent_dir: @dir)}\nIn plain words, this is prose.\n- a prose bullet\n"
    lines = message.lines
    start = lines.index { |l| l.start_with?("## ✔") }
    stop = ScreenPaint.region_end(lines, start)
    assert_operator stop, :>, start
    suffix = lines[stop..].join
    assert_includes suffix, "In plain words, this is prose."
    assert_includes suffix, "- a prose bullet"
    refute_includes suffix, "Needs you"
  end

  # === intent 317a1: palette mapping and three-column field layout ===========

  def wrap_screen(*body_lines)
    (["## ✔ 21 · Demo · delivered", ""] + body_lines).join("\n") + "\n"
  end

  def evidence_table_lines(rows)
    lines = ["| Kind | What | Source |", "| --- | --- | --- |"]
    rows.each { |k, w, s| lines << "| #{k} | #{w} | #{s} |" }
    lines
  end

  # --- O4: evidence kind coloring (D3) -----------------------------------------

  def test_evidence_row_labels_colored_teal_for_every_proof_kind # M1
    kinds = %w[suite red ship doctor deposits verdict]
    rows = kinds.map { |k| [k, "detail for #{k}", "source"] }
    painted = ScreenPaint.paint(wrap_screen(*evidence_table_lines(rows)), color: true)
    refute_nil painted
    kinds.each { |k| assert_includes painted, "#{A::TEAL}#{A::BOLD}#{k}" }
  end

  def test_deviates_kind_colored_amber_and_never_matched_by_content # M2
    ev_painted = ScreenPaint.paint(wrap_screen(*evidence_table_lines([["deviates", "scope narrowed", "outcome.md"]])), color: true)
    assert_includes ev_painted, "#{A::AMBER}#{A::BOLD}deviates"

    delivered_painted = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                                        "| S1 | the plan deviates from spec | 1 test |"), color: true)
    refute_includes delivered_painted, A::AMBER

    # A Kind-headed table proves exact matching, not substring: the prior
    # fixture above has no "Kind" header at all, so the kind-coloring branch
    # never ran and the negative assertion passed for the wrong reason
    # (317a1 post-exec review, finding 2). "deviates from spec" contains the
    # word but is not the word.
    kind_substring_painted = ScreenPaint.paint(wrap_screen(*evidence_table_lines([["deviates from spec", "x", "y"]])), color: true)
    refute_includes kind_substring_painted, A::AMBER
  end

  def test_unrecognized_kind_stays_plain # M3, pin
    painted = ScreenPaint.paint(wrap_screen(*evidence_table_lines([["wat", "something", "somewhere"]])), color: true)
    line = painted.lines.find { |l| l.include?("wat") }
    refute_nil line
    refute_match(/\e\[[0-9;]*mwat/, line)
  end

  def test_kind_rule_does_not_key_on_position # M4, pin
    d = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                       "| A | did the thing | 1 test |"), color: true)
    n = ScreenPaint.paint(wrap_screen("| N | What | Why |", "| --- | --- | --- |",
                                       "| N1 | pick one | ask the owner |"), color: true)
    # "suite" is a real proof-kind word (EVIDENCE_PROOF_KINDS); this table
    # has no "Kind" header, so it must stay plain. Without this row the
    # first-column check above never exercises a value the kind rule would
    # actually color, so a `kind_col = 0` unconditionally mutation survives
    # (317a1 post-exec review, finding 2).
    s = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                       "| suite | ran the tests | outcome.md |"), color: true)
    d_row = d.lines.find { |l| l.include?("did the thing") }
    n_row = n.lines.find { |l| l.include?("pick one") }
    s_row = s.lines.find { |l| l.include?("ran the tests") }
    # The kind-coloring rule only fires for a header literally named "Kind";
    # none of these tables has one, so "A"/"N1"/"suite" must all stay
    # unwrapped by TEAL/AMBER even though Needs-you's own "Why" column
    # legitimately greys.
    refute_match(/\e\[[0-9;]*mA\e\[0m/, d_row)
    refute_match(/\e\[[0-9;]*mN1\e\[0m/, n_row)
    refute_includes d_row, A::TEAL
    refute_includes d_row, A::AMBER
    refute_includes n_row, A::TEAL
    refute_includes n_row, A::AMBER
    refute_includes s_row, A::TEAL
    refute_includes s_row, A::AMBER
  end

  def test_note_column_is_header_driven_not_last_column # M5 (part 1)
    d = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                       "| S1 | did it | 3 tests |"), color: true)
    e = ScreenPaint.paint(wrap_screen(*evidence_table_lines([["suite", "10 runs", "outcome.md"]])), color: true)

    d_row = d.lines.find { |l| l.include?("3 tests") }
    refute_match(/\e\[/, d_row)

    e_row = e.lines.find { |l| l.include?("outcome.md") }
    assert_includes e_row, A::MIDGREY
  end

  def test_not_recorded_proven_by_is_grey_per_d5 # M5 (part 2)
    d = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                       "| S1 | did it | not recorded |"), color: true)
    row = d.lines.find { |l| l.include?("not recorded") }
    assert_includes row, A::MIDGREY
  end

  def test_needs_you_why_column_greyed # M6
    n = ScreenPaint.paint(wrap_screen("| N | What | Why |", "| --- | --- | --- |",
                                       "| N1 | pick a name | owner preference |"), color: true)
    row = n.lines.find { |l| l.include?("owner preference") }
    assert_includes row, A::MIDGREY
  end

  def test_roster_lead_column_plain_and_bars_stay_colored # M7, pin
    roster_text = "▶ In delivery · 1 intent · 2026-08-31 12:00 UTC\n\n" \
      "| Intent | Stage | Progress | Changed | Lead |\n| --- | --- | --- | --- | --- |\n" \
      "| 21 | Exec | ██░░ 1 / 2 | on request | plastic-executor · abc12345 |\n"
    painted = ScreenPaint.paint(roster_text, color: true)
    refute_nil painted
    row = painted.lines.find { |l| l.include?("plastic-executor") }
    refute_match(/#{Regexp.escape(A::TEAL)}plastic-executor/, row)
    assert_includes painted, "#{A::TEAL}██"
    assert_includes painted, "#{A::MIDGREY}░░"
  end

  def test_not_recorded_exact_match_only # M8
    d = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |",
                                       "| S1 | not recorded | not recorded |",
                                       "| S2 | runs not recorded yet | 1 test |"), color: true)
    exact_row = d.lines.find { |l| l =~ /\bS1\b/ }
    substr_row = d.lines.find { |l| l =~ /\bS2\b/ }
    assert_includes exact_row, A::MIDGREY
    refute_includes substr_row, A::MIDGREY
  end

  def test_headers_stay_bold_across_tables # M9, pin
    d = ScreenPaint.paint(wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |", "| S1 | x | y |"), color: true)
    e = ScreenPaint.paint(wrap_screen(*evidence_table_lines([["suite", "x", "y"]])), color: true)
    n = ScreenPaint.paint(wrap_screen("| N | What | Why |", "| --- | --- | --- |", "| N1 | x | y |"), color: true)
    assert_includes d, "#{A::BOLD}Row"
    assert_includes e, "#{A::BOLD}Kind"
    assert_includes n, "#{A::BOLD}N "
  end

  def test_no_trailing_whitespace_hides_inside_color_escape # M10
    # Column widths differ so a padded last cell (row 2's "w", short next to
    # row 1's much longer source) and an EMPTY last cell (row 3) both have
    # something to hide behind a color escape if the guard regresses.
    text = wrap_screen(*evidence_table_lines([["suite", "x", "a longer source value"],
                                               ["wat", "z", "w"],
                                               ["suite", "empty source cell", ""]]))
    painted = ScreenPaint.paint(text, color: true)
    # Padding inside a non-last cell (e.g. "Kind    ") legitimately sits
    # before that cell's own RESET, with more content still to follow on the
    # line; only trailing whitespace on the VISIBLE text - what strip_ansi
    # reveals once the escape codes are gone - is the bug. A raw end-of-line
    # check stays green even when a short or empty styled last cell leaves
    # real trailing spaces hidden behind its own color escape (317a1
    # post-exec review, finding 1); asserting on the raw string is what made
    # the assertion inert. Reverting the "last column stays unpadded" guard
    # (screen_paint.rb's `ci == last_ci` branch) must fail this.
    painted.each_line do |line|
      refute_match(/[ \t]\z/, strip_ansi(line.chomp))
    end
  end

  def test_ragged_row_from_escaped_pipe_does_not_raise # M10b
    raw = "| S1 | text with \\| pipe | 1 test |"
    text = wrap_screen("| Row | What | Proven by |", "| --- | --- | --- |", raw)
    painted = ScreenPaint.paint(text, color: true)
    refute_nil painted
  end

  # --- O5: timeline mapping (D6, D7) -------------------------------------------

  def test_timeline_time_carries_no_escape # M11
    painted = ScreenPaint.paint(wrap_screen("19:00  Review  turning point"), color: true)
    line = painted.lines.find { |l| l.include?("19:00") }
    refute_match(/\e\[[0-9;]*m19:00/, line)
  end

  def test_review_label_amber_bold_exact_match_only # M12
    painted = ScreenPaint.paint(wrap_screen("19:00  Review  time to review the plan"), color: true)
    line = painted.lines.find { |l| l.include?("time to review") }
    assert_includes line, "#{A::BOLD}#{A::AMBER}Review"
    trailing = line.split("Review", 2).last
    refute_includes trailing, A::AMBER
  end

  def test_commit_label_teal_bold # M13
    painted = ScreenPaint.paint(wrap_screen("19:05  Commit  landed the fix"), color: true)
    line = painted.lines.find { |l| l.include?("landed the fix") }
    assert_includes line, "#{A::BOLD}#{A::TEAL}Commit"
  end

  def test_generic_kind_label_midgrey_no_bold # M14
    painted = ScreenPaint.paint(wrap_screen("19:10  What  started planning"), color: true)
    line = painted.lines.find { |l| l.include?("started planning") }
    assert_includes line, A::MIDGREY
    refute_includes line, A::BOLD
  end

  def test_ljust_six_aligns_short_and_long_kind_labels # M15, pin
    painted = ScreenPaint.paint(wrap_screen("19:00  What  short kind", "19:05  Review  long kind name"), color: true)
    plain = strip_ansi(painted)
    what_col = plain.lines.find { |l| l.include?("short kind") }.index("short")
    review_col = plain.lines.find { |l| l.include?("long kind") }.index("long")
    assert_equal what_col, review_col
  end

  # --- O6: indented runs under **Asked** (D8) -----------------------------------

  def test_first_indented_line_plain_second_greyed # M16
    painted = ScreenPaint.paint(wrap_screen("**Asked**", "  do the thing", "  2 decisions in spec.md"), color: true)
    ask_line = painted.lines.find { |l| l.include?("do the thing") }
    note_line = painted.lines.find { |l| l.include?("2 decisions") }
    refute_match(/\e\[/, ask_line)
    assert_includes note_line, A::MIDGREY
  end

  def test_indent_run_resets_across_bold_and_table_lines # M17
    text_lines = [
      "**Asked**",
      "  first block line one",
      "  first block line two",
      "**Another**",
      "  second block line one",
      "  second block line two",
      "| Row | What | Proven by |",
      "| --- | --- | --- |",
      "| S1 | x | y |",
      "  third block line one",
      "  third block line two",
    ]
    painted = ScreenPaint.paint(wrap_screen(*text_lines), color: true)
    refute_nil painted
    %w[first second third].each do |label|
      line = painted.lines.find { |l| l.include?("#{label} block line one") }
      refute_match(/\e\[/, line)
    end
  end

  # --- O3: three-column field table (D9-D11) ------------------------------------

  def test_field_table_note_on_same_line_as_key # M18
    painted = ScreenPaint.paint_table(["| **Stage** | Exec | note about stage |"], color: true, width: 115, markdown_safe: false)
    line = painted.lines.find { |l| l.include?("Exec") }
    assert_includes line, "note about stage"
  end

  def test_field_table_notes_align_at_one_column # M19
    rows = [
      "| **Stage** | Exec | short note |",
      "| **Next** | S3 · a slightly longer value here | another note |",
      "| **Savepoint** | Exec · x | third note |",
    ]
    painted = ScreenPaint.paint_table(rows, color: true, width: 115, markdown_safe: false)
    cols = painted.lines.map { |l| l.index(/short note|another note|third note/) }.compact
    refute_empty cols
    assert_equal [cols.first] * cols.length, cols
  end

  def test_field_table_noteless_row_and_empty_value_have_no_trailing_whitespace # M20
    rows = ["| **Stage** | Exec | |", "| **Next** | | |"]
    painted = ScreenPaint.paint_table(rows, color: true, width: 115, markdown_safe: false)
    painted.each_line { |l| refute_match(/[ \t]\n\z/, l) }
  end

  def test_field_table_basis_ignores_noteless_rows # M21
    rows = [
      "| **Store** | #{'x' * 80} | |",
      "| **Stage** | short | note a |",
      "| **Next** | s | note b |",
    ]
    painted = strip_ansi(ScreenPaint.paint_table(rows, color: true, width: 115, markdown_safe: false))
    stage_line = painted.lines.find { |l| l.include?("note a") }
    next_line = painted.lines.find { |l| l.include?("note b") }
    stage_col = stage_line.index("note a")
    next_col = next_line.index("note b")
    assert_equal stage_col, next_col
    assert_operator stage_col, :<, 30
  end

  # --- O2/O3 shared geometry: over-wide value or note (D11, D15) ---------------

  def test_value_wider_than_value_col_drops_note_to_its_own_line_in_full # M23
    long_value = (["word"] * 15).join(" ") # 74 chars, over the 50 cap
    rows = ["| **Insight** | #{long_value} | a short note |"]
    painted = ScreenPaint.paint_table(rows, color: true, width: 115, markdown_safe: false)
    note_line = painted.lines.find { |l| l.include?("a short note") }
    refute_nil note_line
    key_line = painted.lines.find { |l| l.include?(long_value.split(" ").first) }
    refute_equal key_line, note_line
  end

  def test_note_longer_than_budget_and_floor_drops_to_its_own_line_uncut # M23b
    long_note = (["clauseword"] * 8).join(" ") # 87 chars, over the 50-column budget
    rows = ["| **Insight** | ok | #{long_note} |"]
    painted = ScreenPaint.paint_table(rows, color: true, width: 115, markdown_safe: false)
    plain = strip_ansi(painted)
    assert_includes plain, long_note
    refute_includes plain, "#{long_note[0, long_note.length - 1]}…"
  end

  def test_note_never_silently_drops_at_narrow_width # review fix item 4
    # At width 20 the same-line note budget collapses to 0 (prefix_width 9 +
    # value_col 9 + 2 == 20). An unguarded same-line branch still thought
    # the note "fit" (its length is under NOTE_FLOOR) and fed it to
    # `fit(note, 0)`, which returns "" with no ellipsis - the note vanished
    # outright rather than being cut (317a1 post-exec review, finding 4).
    rows = ["| **Stage** | Execution | short |"]
    painted = ScreenPaint.paint_table(rows, color: true, width: 20, markdown_safe: false)
    plain = strip_ansi(painted)
    assert_includes plain, "short"
  end

  def test_content_survives_in_full_at_generous_width_and_only_ellipsis_marks_a_cut # M24, M28
    value = "V" * 200
    note = "N" * 200
    rows = ["| **Insight** | #{value} | #{note} |"]

    wide = ScreenPaint.paint_table(rows, color: false, width: 400, markdown_safe: false)
    assert_includes wide, value
    assert_includes wide, note

    narrow = ScreenPaint.paint_table(rows, color: false, width: 115, markdown_safe: false)
    refute_includes narrow, value
    refute_includes narrow, note
    narrow.lines.each do |line|
      text = line.chomp
      next if text.strip.empty?
      assert text.end_with?("…"), "expected a visible ellipsis on a shortened line: #{text.inspect}"
      refute text.length > 115, "field-table line exceeded the width cap: #{text.inspect}"
    end
  end

  # --- O3: state screen and roster regression guards ----------------------------

  def test_state_screen_keeps_approved_look_with_data_table_step_cells # M26, pin
    painted = ScreenPaint.paint(state_screen, color: true)
    assert_includes painted, "#{A::BOLD}#{A::NEARWHITE}"
    assert_includes painted, "#{A::BOLD}Store"
    # The Steps data-table row starts with "S1"/"S2"; the field table's own
    # "Next" row also contains "second step open" as its value text, so the
    # match must anchor on the step row's own leading label, not the phrase.
    step_done_line = painted.lines.find { |l| l.strip.start_with?("S1") }
    step_open_line = painted.lines.find { |l| l.strip.start_with?("S2") }
    refute_nil step_done_line
    refute_nil step_open_line
    assert_includes step_done_line, A::TEAL
    assert_includes step_open_line, A::AMBER
  end

  def test_roster_collapsed_block_badge_survives # M26b, pin
    out = ReportScreen.render_roster(@root, changed: nil)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    # Same anchoring caveat as above: the collapsed block's own "Next" line
    # also contains "second step open" as its value text.
    badge_line = painted.lines.find { |l| l.strip.start_with?("S2") }
    refute_nil badge_line
    assert_includes badge_line, A::AMBER
  end

  def test_color_false_never_emits_escape_bytes_for_new_mappings # M27, pin
    text = wrap_screen(*evidence_table_lines([["suite", "x", "y"], ["deviates", "z", "w"]]))
    painted = ScreenPaint.paint(text, color: false)
    refute_includes painted, ESC
  end

  def test_short_and_narrow_tables_do_not_break_header_lookup # M29, pin
    one_col = ScreenPaint.paint(wrap_screen("| Solo |", "| --- |", "| value |"), color: true)
    two_col = ScreenPaint.paint(wrap_screen("| A | B |", "| --- | --- |", "| x | y |"), color: true)
    refute_nil one_col
    refute_nil two_col
  end

  def test_prose_line_still_fails_open # M30, pin
    text = wrap_screen("**Asked**", "  indented value", "this is ordinary unindented prose")
    assert_nil ScreenPaint.paint(text, color: true)
  end

  def test_markdown_safe_strips_backticks_inside_colored_cells # M31, pin
    text = wrap_screen(*evidence_table_lines([["suite", "touch `scripts/lib/lock.rb` carefully", "outcome.md"]]))
    painted = ScreenPaint.paint(text, color: true, markdown_safe: true)
    plain = strip_ansi(painted)
    assert_includes plain, "scripts/lib/lock.rb"
    refute_includes plain, "`"
  end

  def test_standalone_not_recorded_line_stays_greyed # M32, pin
    painted = ScreenPaint.paint(wrap_screen("**Evidence**", "not recorded"), color: true)
    line = painted.lines.find { |l| l.include?("not recorded") }
    assert_includes line, A::MIDGREY
  end

  def test_none_closer_stays_greyed # M33, pin
    painted = ScreenPaint.paint(wrap_screen("**Needs you**", "None"), color: true)
    line = painted.lines.find { |l| l.include?("None") }
    assert_includes line, A::MIDGREY
  end

  # === intent 331a (D6): the ScreenPaint registry ============================
  #
  # register(kind, opener:, paint: nil) plus a kind-agnostic classify/paint
  # so a new screen kind lives in scripts/lib/screens/<kind>.rb and calls
  # register on load, never editing this file. paint: is optional and
  # defaults to the shared pipeline below - no shipped kind has its own
  # palette (D6 refinement).

  def teardown_registry(kind)
    ScreenPaint.instance_variable_get(:@registry)&.delete(kind)
  end

  def test_register_is_idempotent_by_kind # R1
    ScreenPaint.register(:demo_r1_331a, opener: /\A~~ first ~~/)
    ScreenPaint.register(:demo_r1_331a, opener: /\A~~ second ~~/)
    assert_equal 1, ScreenPaint.kinds.count(:demo_r1_331a)
  ensure
    teardown_registry(:demo_r1_331a)
  end

  def test_registered_opener_classifies_as_opener # R2
    ScreenPaint.register(:demo_r2_331a, opener: /\A~~ demo ~~ /)
    assert_equal :opener, ScreenPaint.classify("~~ demo ~~ hello\n")
  ensure
    teardown_registry(:demo_r2_331a)
  end

  def test_registry_paint_entry_is_invoked_for_its_kind # R3
    sentinel = "PAINTED-BY-DEMO-KIND-331A"
    ScreenPaint.register(:demo_r3_331a, opener: /\A~~ demo3 ~~/, paint: ->(_text, **_opts) { sentinel })
    out = ScreenPaint.paint("~~ demo3 ~~ hello\nmore body\n", color: true)
    assert_equal sentinel, out
  ensure
    teardown_registry(:demo_r3_331a)
  end

  def test_five_shipped_kinds_are_registered # R4
    %i[intent state roster delivered delay].each do |kind|
      assert_includes ScreenPaint.kinds, kind
    end
  end

  def test_new_kind_file_registers_without_painter_edit # R5
    lib_path = File.expand_path("../scripts/lib/screen_paint.rb", __dir__)
    before = File.read(lib_path)
    Dir.mktmpdir("screen-kind-331a") do |dir|
      path = File.join(dir, "demo_kind_331a.rb")
      File.write(path, <<~RUBY)
        require "#{lib_path}"
        ScreenPaint.register(:demo_file_kind_331a, opener: /\\A~~ demo file ~~/)
      RUBY
      require path
    end
    assert_includes ScreenPaint.kinds, :demo_file_kind_331a
    assert_equal before, File.read(lib_path)
  ensure
    teardown_registry(:demo_file_kind_331a)
  end

  def test_region_end_stops_at_prose_for_registered_kind # R6
    ScreenPaint.register(:demo_r6_331a, opener: /\A~~ demo6 ~~/)
    text = "~~ demo6 ~~ hello\n| a | b |\nordinary trailing prose, not grammar\n"
    stop = ScreenPaint.region_end(text.lines, 0)
    assert_equal 2, stop
  ensure
    teardown_registry(:demo_r6_331a)
  end

  # --- intent 331c: roadmap screen kinds (D7) -----------------------------------

  # R13: without scripts/lib/screens/roadmap.rb, the roadmap screen kinds are not
  # registered at all - a future custom palette for one of them would have nowhere to live.
  def test_roadmap_kinds_paint
    require_relative "../scripts/lib/screens/roadmap"
    %i[roadmap_plan roadmap_state roadmap_delivered].each do |kind|
      assert_includes ScreenPaint.kinds, kind, "#{kind} must be registered so its opener is recognized"
    end
  end

  # R19: the delivered template's meta line sits directly under the title (no blank line, the
  # plan review's binding finding 5); a real render of all three roadmap verbs must paint, never
  # silently fall back to plain because a blank line defeated ScreenPaint.classify's :meta rule.
  def test_rendered_roadmap_screens_all_paint
    Dir.mktmpdir("roadmap-paint-331c") do |home|
      roadmaps = File.join(home, "roadmaps")
      FileUtils.mkdir_p(roadmaps)
      File.write(File.join(roadmaps, "demo.md"), <<~MD)
        # Roadmap: Demo
        ## Goal
        test goal.
        ## Batches
        ### Batch 1
        - [x] 1 Alpha — delivered
        ## Log
        - 2026-07-10 00:00 UTC created.
      MD
      File.write(File.join(home, "INDEX.md"), <<~IDX)
        # Index

        ## Active

        ## Future

        ## Completed
        - [1 — Alpha](store/1--alpha/1--alpha.md) — 2026-07-10 delivered.

        ## Abandoned
      IDX
      File.write(File.join(roadmaps, "demo.savepoint.md"), <<~LEDGER)
        2026-07-10T00:00:00Z  created  demo
        2026-07-10T00:10:00Z  merged  1 merged into alpha at abc1234
        2026-07-10T00:20:00Z  closed  demo closed
      LEDGER

      %w[plan state delivered].each do |verb|
        out = ReportScreen.render_roadmap(path: File.join(roadmaps, "demo.md"), verb: verb, store_root: home)
        painted = ScreenPaint.paint(out, color: true)
        refute_nil painted, "#{verb} roadmap screen must paint, never silently fall back to plain"
      end
    end
  # --- intent 331b: the plan kind (scripts/lib/screens/plan.rb) ---------------

  def plan_screen
    require_relative "../scripts/lib/screens/plan"
    template = File.read(File.expand_path("../templates/report-plan.md", __dir__))
    ReportScreen.render_plan(intent_dir: @dir, store_root: @root, template: template)
  end

  def test_plan_screen_paints_through_the_shared_pipeline # P10
    painted = ScreenPaint.paint(plan_screen, color: true)
    refute_nil painted
    plain = strip_ansi(painted)
    assert_includes plain, "plan"
    refute_match(/^\s*\|/, plain)
  end

  def test_plan_registration_leaves_the_five_shipped_kinds_resolving_as_before # P10a
    require_relative "../scripts/lib/screens/plan"
    assert_equal :intent, ScreenPaint.opener_kind("## ▶ 21 · Paint demo")
    # :intent's opener already matches this shape too (pre-existing, before
    # :plan ever registers) - the same shadowing F1 documents for the plan
    # title; :plan must not change that.
    assert_equal :intent, ScreenPaint.opener_kind("## ✔ 21 · Paint demo · delivered")
    assert_equal :roster, ScreenPaint.opener_kind("▶ In delivery · 1 open")
    assert_equal :delay, ScreenPaint.opener_kind("✔ 21 · Paint demo · delivered in 10 min")
    # F1: :intent's opener already matches a plan title, so :plan (registered
    # last) is shadowed - the fact D4 rests on, never accidentally reversed by
    # narrowing :intent's opener from screens/plan.rb.
    assert_equal :intent, ScreenPaint.opener_kind("## ▶ 21 · Paint demo · plan")
    assert_includes ScreenPaint.kinds, :plan
  end

  def test_plan_kind_registers_without_editing_screen_paint # P10b
    lib_path = File.expand_path("../scripts/lib/screen_paint.rb", __dir__)
    before = File.read(lib_path)
    require_relative "../scripts/lib/screens/plan"
    assert_includes ScreenPaint.kinds, :plan
    assert_equal before, File.read(lib_path)
  end
end
