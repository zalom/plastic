require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/intent_screen"

# Intent 317, D3/D4/D7/D8/D9: the `state` verb for one intent (templates/report-state.md)
# and the `state --all` roster. Field values must equal the live IntentScreen call's
# (never a hardcoded literal, so 316a's landing changes cannot break this suite);
# notes form a column, padded on both label and value, computed on raw emitted text.
class ReportScreenStateTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  TEMPLATE = File.join(REPO, "templates", "report-state.md")

  def setup
    @home = Dir.mktmpdir("report-screen-state")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def tier_root(slug: "demo")
    root = File.join(@home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, entries)
    sections = { "Active" => [], "Future" => [], "Completed" => [], "Abandoned" => [] }
    entries.each { |id, title, section| sections[section] << "- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags\n" }
    body = +"# Index\n\n"
    sections.each { |name, lines| body << "## #{name}\n#{lines.join}\n" }
    File.write(File.join(root, "INDEX.md"), body)
  end

  def make_intent(root, id: "12", title: "Demo intent", checklist: nil, savepoint: nil)
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    body = +"---\nid: #{id}\nintent: \"#{title}\"\nsources: []\nchain: []\ncreated: 2026-08-30\nauthor: human\ntags: [demo]\n---\n\n"
    body << "## Intent\n#{title}\n\n## Context\nx\n\n## Outcome\n\n## Insights\n"
    File.write(File.join(dir, "#{id}--slug.md"), body)
    File.write(File.join(dir, "checklist.md"), checklist) if checklist
    File.write(File.join(dir, "savepoint.md"), savepoint) if savepoint
    dir
  end

  def checklist_with(total:, done:)
    items = (1..total).map { |n| "- [#{n <= done ? 'x' : ' '}] Step #{n} - do thing #{n}" }
    "# Checklist\n\n## In Progress\n#{items.join("\n")}\n\n## Completed\n\n## Session Log\n"
  end

  HOW_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze

  def row(screen, field)
    line = screen.lines.find { |l| l.start_with?("| **#{field}**") || l.start_with?("| #{field} |") || l.include?("**#{field}**") }
    refute_nil line, "no #{field} row in:\n#{screen}"
    cells = line.split("|").map(&:strip)
    { label: cells[1], value: cells[2], note: cells[3] }
  end

  # --- row 39: field values equal the live IntentScreen.render's --------------

  def test_field_values_equal_the_live_intent_screen_call
    root = tier_root
    write_index(root, [["12", "Demo intent", "Active"]])
    dir = make_intent(root, checklist: checklist_with(total: 4, done: 1), savepoint: HOW_LEDGER)

    intent_template = File.read(File.join(REPO, "templates", "intent-screen.md"))
    reference = IntentScreen.render(intent_dir: dir, store_root: root, template: intent_template)

    screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: nil, template: File.read(TEMPLATE))

    %w[Store Status Stage Savepoint Next Insight].each do |field|
      ref_val = row(reference, field)[:value]
      got_val = row(screen, field)[:value]
      assert_equal ref_val, got_val, "field #{field} diverged from the live IntentScreen call"
    end
  end

  # --- row 40/41: Changed field (D9) ------------------------------------------

  def test_changed_flag_present_and_last
    root = tier_root
    write_index(root, [["12", "Demo intent", "Active"]])
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: "How written, plan review next", template: File.read(TEMPLATE))
    changed = row(screen, "Changed")
    assert_equal "How written, plan review next", changed[:value]

    field_lines = screen.lines.select { |l| l =~ /^\| \*\*\w/ }
    assert_match(/Changed/, field_lines.last)
  end

  def test_changed_defaults_to_on_request
    root = tier_root
    write_index(root, [["12", "Demo intent", "Active"]])
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: nil, template: File.read(TEMPLATE))
    assert_equal "on request", row(screen, "Changed")[:value]
  end

  # --- rows 42-46: padding, tested directly on the row-building function ------
  #
  # state_rows takes [label, value, note] triples (the same shape render_state
  # assembles from the live field methods) and pads BOTH columns to the widest
  # NOTED label/value, computed on the raw emitted (escaped) text; unnoted rows
  # are not padded, and a screen with no notes at all is not padded either.

  def test_state_rows_pads_both_columns_to_the_widest_noted_value
    lines = ReportScreen.state_rows([
      ["Store", "global", "the global store"],
      ["Savepoint", "How · checklist.md created", "2026-08-30 12:00 UTC"],
    ])
    offsets = lines.map { |l| l.split("|")[1..2].join("|").length }
    assert_equal 1, offsets.uniq.length, "every noted row's note must begin at the same offset:\n#{lines.join("\n")}"
  end

  def test_padding_width_source_is_the_widest_noted_value_only
    lines = ReportScreen.state_rows([
      ["Next", "a very long unnoted value indeed, much longer than anything else here", ""],
      ["Insight", "short", "a note"],
    ])
    insight_line = lines.find { |l| l.include?("Insight") }
    # the value column width must come from "short" (the noted row), not from
    # the long unnoted Next value.
    value_cell = insight_line.split("|")[2]
    assert_equal "short".length, value_cell.strip.length
  end

  def test_padding_excludes_unnoted_rows
    lines = ReportScreen.state_rows([
      ["Store", "global", "the global store"],
      ["Next", "", ""],
    ])
    unnoted = lines.find { |l| l.include?("Next") }
    assert_match(/\|\s*\|\s*\z/, unnoted, "an unnoted row must carry no padding")
  end

  def test_no_notes_at_all_means_no_padding
    lines = ReportScreen.state_rows([
      ["Store", "global", ""],
      ["Status", "Active", ""],
    ])
    lines.each { |l| assert_match(/\|\s*\|\s*\z/, l) }
  end

  def test_padding_computed_on_raw_emitted_text_including_escaping
    lines = ReportScreen.state_rows([
      ["Next", "a|b", "note one"],
      ["Insight", "cd", "note two"],
    ])
    # "a|b" escapes to "a\|b" (4 raw chars), wider than "cd" (2 chars): the
    # value column must pad to 4, computed on the ESCAPED text, not the
    # 3-char unescaped "a|b". A naive split("|") cannot read the escaped
    # value cell directly (it would also split on the escaped pipe), so this
    # is asserted through the shorter Insight row's padding instead.
    insight_line = lines.find { |l| l.include?("Insight") }
    assert_includes insight_line, "cd  ", "Insight's value must pad out to width 4 (the escaped Next value's width)"
  end

  def test_pipe_in_value_still_aligns_through_render_state
    root = tier_root
    write_index(root, [["12", "Demo intent", "Active"]])
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - grep `a|b` in the file\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: "x", template: File.read(TEMPLATE))
    assert_includes screen, "a\\|b"
  end

  # --- row 47: table still parses after escaping -------------------------------

  def test_table_still_parses_with_escaped_pipe
    root = tier_root
    write_index(root, [["12", "Demo intent", "Active"]])
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - a | b\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    screen = ReportScreen.render_state(intent_dir: dir, store_root: root, changed: "x", template: File.read(TEMPLATE))
    field_lines = screen.lines.select { |l| l.start_with?("| **") }
    field_lines.each { |l| assert_equal 4, l.count("|") - l.scan("\\|").length, "row is not a well-formed 3-cell table row: #{l}" }
  end

  # =============================================================================
  # state --all roster (S5)
  # =============================================================================

  # --- row 48: membership excludes terminal sections ---------------------------

  def test_roster_membership_excludes_terminal_sections
    root = tier_root
    write_index(root, [["10", "Active one", "Active"], ["11", "Future one", "Future"],
                        ["12", "Completed one", "Completed"], ["13", "Abandoned one", "Abandoned"]])
    make_intent(root, id: "10", title: "Active one", checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    entries = ReportScreen.roster(root)
    assert_equal ["10"], entries.map { |e| e[:id] }
  end

  # --- row 49: Active but Done-delivered ledger is excluded --------------------

  def test_roster_excludes_active_intent_whose_ledger_ended_done
    root = tier_root
    write_index(root, [["10", "Active but done", "Active"]])
    make_intent(root, id: "10", title: "Active but done", checklist: checklist_with(total: 1, done: 1),
                savepoint: HOW_LEDGER + "2026-08-30T13:00:00Z  Done  delivered\n")
    entries = ReportScreen.roster(root)
    assert_equal [], entries
  end

  # --- row 50/51: ordering, newest of ANY line first ---------------------------

  def test_roster_orders_by_newest_savepoint_of_any_line
    root = tier_root
    write_index(root, [["10", "Old", "Active"], ["11", "Newer", "Active"], ["12", "Newest via commit", "Active"]])
    make_intent(root, id: "10", title: "Old", checklist: checklist_with(total: 1, done: 0),
                savepoint: "2026-08-30T09:00:00Z  What  10--slug.md\n")
    make_intent(root, id: "11", title: "Newer", checklist: checklist_with(total: 1, done: 0),
                savepoint: "2026-08-30T10:00:00Z  What  11--slug.md\n")
    make_intent(root, id: "12", title: "Newest via commit", checklist: checklist_with(total: 1, done: 0),
                savepoint: "2026-08-30T08:00:00Z  What  12--slug.md\n2026-08-30T11:00:00Z  Commit  abc1234 tests green\n")
    entries = ReportScreen.roster(root)
    assert_equal %w[12 11 10], entries.map { |e| e[:id] }
  end

  # --- row 52: tie-break by id ascending, stable across runs -------------------

  def test_roster_tie_break_by_id_ascending
    root = tier_root
    write_index(root, [["12", "B", "Active"], ["10", "A", "Active"]])
    ts = "2026-08-30T09:00:00Z"
    make_intent(root, id: "12", title: "B", checklist: checklist_with(total: 1, done: 0), savepoint: "#{ts}  What  12--slug.md\n")
    make_intent(root, id: "10", title: "A", checklist: checklist_with(total: 1, done: 0), savepoint: "#{ts}  What  10--slug.md\n")
    first = ReportScreen.roster(root).map { |e| e[:id] }
    second = ReportScreen.roster(root).map { |e| e[:id] }
    assert_equal %w[10 12], first
    assert_equal first, second
  end

  # --- row 53: Lead (D18) -------------------------------------------------------

  def test_lead_reads_the_lock_owner_agent_and_session
    root = tier_root
    dir = make_intent(root, id: "10", title: "A", checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    File.write(File.join(dir, "delivery.lock"),
               { "owner_session" => "abcdef1234567890", "owner_agent" => "plastic-enforcer" }.to_json)
    assert_equal "plastic-enforcer · abcdef12", ReportScreen.lead(dir)
  end

  def test_lead_absent_lock_renders_idle
    root = tier_root
    dir = make_intent(root, id: "10", title: "A", checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    assert_equal "idle", ReportScreen.lead(dir)
  end

  def test_lead_unreadable_lock_renders_idle
    root = tier_root
    dir = make_intent(root, id: "10", title: "A", checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    File.write(File.join(dir, "delivery.lock"), "not json")
    assert_equal "idle", ReportScreen.lead(dir)
  end

  # --- row 54: collapsed block shows exactly Stage, Next, Changed --------------

  def test_collapsed_block_shows_exactly_three_fields
    root = tier_root
    dir = make_intent(root, id: "10", title: "A", checklist: checklist_with(total: 5, done: 1), savepoint: HOW_LEDGER)
    block = ReportScreen.render_collapsed_block(dir, root, changed: "How written")
    assert_includes block, "Stage"
    assert_includes block, "Next"
    assert_includes block, "Changed"
    refute_includes block, "Progress"
    refute_includes block, "Insight"
    refute_includes block, "Store"
  end

  # --- row 55: first three OPEN steps, done skipped ----------------------------

  def test_collapsed_block_shows_first_three_open_steps
    root = tier_root
    cl = <<~CL
      # Checklist

      ## In Progress
      - [x] Step 1 - done one
      - [x] Step 2 - done two
      - [ ] Step 3 - open three
      - [ ] Step 4 - open four
      - [ ] Step 5 - open five
      - [ ] Step 6 - open six
    CL
    dir = make_intent(root, id: "10", title: "A", checklist: cl, savepoint: HOW_LEDGER)
    block = ReportScreen.render_collapsed_block(dir, root, changed: "x")
    assert_includes block, "4 open · showing the first three"
    assert_includes block, "S3"
    assert_includes block, "open three"
    assert_includes block, "S5"
    assert_includes block, "open five"
    refute_includes block, "done one"
  end

  # --- row 56: fewer than three open steps -------------------------------------

  def test_collapsed_block_with_one_open_step
    root = tier_root
    cl = "# Checklist\n\n## In Progress\n- [x] Step 1 - done one\n- [ ] Step 2 - open two\n"
    dir = make_intent(root, id: "10", title: "A", checklist: cl, savepoint: HOW_LEDGER)
    block = ReportScreen.render_collapsed_block(dir, root, changed: "x")
    assert_includes block, "1 open"
    refute_includes block, "showing the first three"
  end

  # --- row 57: empty roster renders one honest line, exit 0 --------------------

  def test_empty_roster_renders_one_line
    root = tier_root
    write_index(root, [])
    out = ReportScreen.render_roster(root, changed: nil, now: Time.utc(2026, 8, 31, 11, 30, 0))
    refute_includes out, "| Intent |"
    assert_equal 1, out.strip.lines.length
  end
end
