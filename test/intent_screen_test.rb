require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/intent_screen"

# Intent 316: the intent screen. IntentScreen.render fills templates/intent-screen.md
# from one intent's record (intent file, INDEX.md section, savepoint.md, checklist.md)
# so no number on the screen is written by eye. Pure: explicit paths, no ENV, no Dir.pwd.
class IntentScreenTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  TEMPLATE = File.join(REPO, "templates", "intent-screen.md")
  CLI = File.join(REPO, "scripts", "intent-screen")

  def setup
    @home = Dir.mktmpdir("intent-screen")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- fixture builders ---------------------------------------------------------

  def tier_root(kind, slug: "demo")
    root = kind == :global ? @home : File.join(@home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, section, id, title)
    File.write(File.join(root, "INDEX.md"), <<~MD)
      # Index

      ## Active
      #{section == "Active" ? index_line(id, title) : ""}
      ## Future
      #{section == "Future" ? index_line(id, title) : ""}
      ## Completed
      #{section == "Completed" ? index_line(id, title) : ""}
      ## Abandoned
      #{section == "Abandoned" ? index_line(id, title) : ""}
    MD
  end

  def index_line(id, title)
    "- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags, summary\n"
  end

  def make_intent(root, id: "12", title: "Demo intent", section: "Active",
                  checklist: nil, savepoint: nil, insights: [])
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    write_index(root, section, id, title) if section
    body = +"---\nid: #{id}\nintent: \"A long intent sentence that is not the title\"\n"
    body << "sources: []\nchain: []\ncreated: 2026-08-30\nauthor: human\ntags: [demo]\n---\n\n"
    body << "## Intent\nx\n\n## Context\nx\n\n## Outcome\n\n## Insights\n"
    insights.each { |line| body << line << "\n" }
    body << "\n## Links\n"
    File.write(File.join(dir, "#{id}--slug.md"), body)
    File.write(File.join(dir, "checklist.md"), checklist) if checklist
    File.write(File.join(dir, "savepoint.md"), savepoint) if savepoint
    dir
  end

  def checklist_with(total:, done:)
    items = (1..total).map do |n|
      mark = n <= done ? "x" : " "
      "- [#{mark}] Step #{n} - do thing #{n}"
    end
    "# Checklist: Demo\n\n## In Progress\n#{items.join("\n")}\n\n## Completed\n\n## Session Log\n"
  end

  PLACEHOLDER = "<!-- plastic:placeholder -->\n# Checklist: {{INTENT_NAME}}\n\n## In Progress\n- [ ] ...\n".freeze
  HOW_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze

  def render(dir, root)
    IntentScreen.render(intent_dir: dir, store_root: root, template: File.read(TEMPLATE))
  end

  def row(screen, field)
    line = screen.lines.find { |l| l.start_with?("| **#{field}** |") }
    refute_nil line, "no #{field} row in:\n#{screen}"
    cells = line.split("|").map(&:strip)
    { value: cells[2], note: cells[3] }
  end

  def step_rows(screen)
    screen.lines.select { |l| l =~ /^\| S\d+ \|/ || l.start_with?("| | | no steps yet") }
  end

  # --- progress ----------------------------------------------------------------

  def test_progress_counts_and_bar
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 23, done: 7), savepoint: HOW_LEDGER)
    r = row(render(dir, root), "Progress")
    assert_equal "#{'█' * 6}#{'░' * 14} 7 / 23", r[:value]
    assert_equal "16 steps open", r[:note]
  end

  def test_placeholder_checklist_renders_zero_over_zero
    root = tier_root(:project)
    dir = make_intent(root, checklist: PLACEHOLDER, savepoint: "2026-08-30T12:00:00Z  What  12--slug.md\n")
    screen = render(dir, root)
    assert_equal "#{'░' * 20} 0 / 0", row(screen, "Progress")[:value]
    assert_equal "no checklist yet", row(screen, "Progress")[:note]
    assert_equal "write checklist.md", row(screen, "Next")[:value]
    assert_equal ["| | | no steps yet |"], step_rows(screen).map(&:strip)
  end

  # --- stage -------------------------------------------------------------------

  def test_what_only_ledger_lands_at_why
    root = tier_root(:project)
    dir = make_intent(root, savepoint: "2026-08-30T12:00:00Z  What  12--slug.md\n")
    screen = render(dir, root)
    assert_equal "Why", row(screen, "Stage")[:value]
    assert_equal "What · 12--slug.md", row(screen, "Savepoint")[:value]
    assert_equal "2026-08-30 12:00 UTC", row(screen, "Savepoint")[:note]
  end

  def test_how_checklist_created_lands_at_exec
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 3, done: 0), savepoint: HOW_LEDGER)
    screen = render(dir, root)
    assert_equal "Exec", row(screen, "Stage")[:value]
    assert_equal "What, How delivered; the work is open", row(screen, "Stage")[:note]
  end

  # --- status ------------------------------------------------------------------

  def test_completed_intent_has_empty_next
    root = tier_root(:project)
    ledger = HOW_LEDGER + "2026-08-30T13:00:00Z  Done  delivered\n"
    dir = make_intent(root, section: "Completed", checklist: checklist_with(total: 2, done: 2), savepoint: ledger)
    screen = render(dir, root)
    assert_equal "Completed", row(screen, "Status")[:value]
    assert_equal "listed under ## Completed in INDEX.md", row(screen, "Status")[:note]
    assert_equal "", row(screen, "Next")[:value]
    assert_equal "Done", row(screen, "Stage")[:value]
  end

  def test_unlisted_intent_says_unlisted
    root = tier_root(:project)
    dir = make_intent(root, section: nil, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    write_index(root, "Active", "99", "Someone else")
    assert_equal "unlisted", row(render(dir, root), "Status")[:value]
  end

  # --- steps -------------------------------------------------------------------

  def test_pipe_in_item_text_is_escaped
    root = tier_root(:project)
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - grep `a|b` in the file\n- [x] Step 2 - plain\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    rows = step_rows(render(dir, root)).map(&:strip)
    assert_equal 2, rows.length
    assert_equal "| S1 | open | grep `a\\|b` in the file |", rows[0]
    assert_equal "| S2 | done | plain |", rows[1]
  end

  def test_step_prefix_stripped_once
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER)
    screen = render(dir, root)
    assert_equal "S2 · do thing 2", row(screen, "Next")[:value]
    assert_equal "first open step", row(screen, "Next")[:note]
    assert_includes screen, "| S2 | open | do thing 2 |"
    refute_includes screen, "Step 2 -"
  end

def test_next_shows_first_clause_full_text_in_table
  root = tier_root(:project)
  cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - Doctor full on the real install; OPEN: codex_integrity passes although the registrations are stale\n"
  dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
  screen = render(dir, root)
  assert_equal "S1 · Doctor full on the real install", row(screen, "Next")[:value]
  assert_includes screen, "| S1 | open | Doctor full on the real install; OPEN: codex_integrity passes although the registrations are stale |"
end

  # O1c, matrix row 8 (second half): a step well over STEP_TEXT_MAX (110) is cut
  # at a word boundary with a trailing "…", never mid-word — and never via a
  # clause trim, which the pinned row above already proves would be wrong.
  def test_long_step_text_word_boundary_truncated_at_110
    root = tier_root(:project)
    long_text = (["word"] * 30).join(" ") # 149 characters, no punctuation at all
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - #{long_text}\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    rows = step_rows(render(dir, root)).map(&:strip)
    cell = rows.first[/\A\| S1 \| open \| (.*) \|\z/, 1]
    refute_nil cell
    assert cell.length <= 110, "expected <= 110 chars, got #{cell.length}: #{cell.inspect}"
    assert cell.end_with?("…"), "expected a trailing ellipsis: #{cell.inspect}"
    refute_match(/\Aword(?: word)*\z/, cell) # sanity: it really was cut, not left whole
  end

  # O1e, matrix row 10b: an em dash or en dash separator kept its prefix under
  # the old character class ([-:·]) and rendered "S1  [ open ]  S1 — text".
  def test_em_dash_and_en_dash_step_prefixes_are_stripped
    root = tier_root(:project)
    cl = "# Checklist\n\n## In Progress\n- [ ] S1 — Live evidence first\n- [ ] S2 – another one\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    screen = render(dir, root)
    assert_includes screen, "| S1 | open | Live evidence first |"
    assert_includes screen, "| S2 | open | another one |"
    refute_includes screen, "S1 — Live evidence first"
    refute_includes screen, "S2 – another one"
  end

  # --- insight: the multi-clause defect (O1a, matrix rows 1-3) -----------------

  def test_insight_value_ends_on_whole_clause_within_72_with_ellipsis
    root = tier_root(:project)
    entries = [multi_clause_insight_entry]
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER, insights: entries)
    r = row(render(dir, root), "Insight")

    assert r[:value].length <= 72, "value exceeded 72: #{r[:value].inspect}"
    assert r[:value].end_with?("…"), "expected a truncation ellipsis: #{r[:value].inspect}"
    refute_includes r[:value], "THIRDCLAUSEMARKER"
    refute_includes r[:value], "row D was ruled"
  end

  def test_insight_note_carries_at_most_one_clause_within_96
    root = tier_root(:project)
    entries = [multi_clause_insight_entry]
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER, insights: entries)
    r = row(render(dir, root), "Insight")

    assert_match(/\A2026-08-30 20:51 UTC · /, r[:note])
    clause = r[:note].sub("2026-08-30 20:51 UTC · ", "")
    assert clause.length <= 96, "note clause exceeded 96: #{clause.inspect}"
    refute_includes r[:note], "THIRDCLAUSEMARKER"
    # never more than one clause: only one "·" separator (the timestamp's own)
    assert_equal 1, r[:note].scan(" · ").length
  end

  def multi_clause_insight_entry
    clause1 = "Doctor delivered the seven code rows A, B, C, E, F, G, H found by this whole verification pass"
    clause2 = "row D was ruled configuration rather than a defect because flow base already overrides origin detection reliably every time"
    clause3 = "THIRDCLAUSEMARKER must never reach the rendered screen no matter what"
    "2026-08-30T20:51:18Z · Exec · orchestrator (autonomous) — #{clause1}. #{clause2}; #{clause3}."
  end

  # --- store and title -----------------------------------------------------------

  def test_project_path_shows_project_slug
    root = tier_root(:project, slug: "plastic")
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    r = row(render(dir, root), "Store")
    assert_equal "project:plastic", r[:value]
    assert_equal "the plastic project store", r[:note]
  end

  def test_global_path_shows_global
    root = tier_root(:global)
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    r = row(render(dir, root), "Store")
    assert_equal "global", r[:value]
    assert_equal "the global store", r[:note]
  end

  def test_title_uses_index_terse_title
    root = tier_root(:project)
    dir = make_intent(root, title: "The intent screen", checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    assert_equal "## ▶ 12 · The intent screen", render(dir, root).lines.first.strip
  end

  # --- insight -----------------------------------------------------------------

  def test_last_insight_value_and_dated_note
    root = tier_root(:project)
    entries = [
      "2026-08-30T12:06:18Z · Exec · orchestrator (direct) — First entry. With a tail.",
      "2026-08-30T12:10:02Z · Exec · orchestrator (direct) — Codex re-synced to alpha.2; both harnesses share the 2.0 core.",
    ]
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER, insights: entries)
    r = row(render(dir, root), "Insight")
    assert_equal "Codex re-synced to alpha.2", r[:value]
    assert_equal "2026-08-30 12:10 UTC · both harnesses share the 2.0 core.", r[:note]
  end

  def test_no_insights_says_none_yet
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    assert_equal "none yet", row(render(dir, root), "Insight")[:value]
  end

  # --- template ----------------------------------------------------------------

  def test_no_placeholder_survives
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER)
    screen = render(dir, root)
    refute_match(/\{\{[a-z.]+\}\}/, screen)
    # O1b (intent 316a): the "What this means" heading is omitted entirely when
    # meaning is empty (always true here, since render() never fills it), rather
    # than rendering as a bold heading over nothing. Rewritten, not deleted: this
    # still proves no {{meaning}}/{{close}} token survives.
    refute_includes screen, "**What this means**"
    refute_includes screen, "{{meaning}}"
    refute_includes screen, "{{close}}"
    assert_includes screen, "| Step | Status | What |"
  end

  # O1b, matrix row 6: a blank-line assertion proves nothing (render already
  # collapses \n{3,}); assert the exact text on both sides of the dropped
  # "What this means" section instead. Steps follows the Insight row directly.
  def test_meaning_section_dropped_steps_follows_insight_directly
    root = tier_root(:project)
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER)
    screen = render(dir, root)
    assert_includes screen, "| **Insight** | none yet |  |\n\n**Steps**\n\n| Step | Status | What |"
  end

  # --- CLI ---------------------------------------------------------------------

  def test_cli_exits_two_on_non_intent_dir
    day = File.join(@home, "store", ".sessions", "20260830")
    FileUtils.mkdir_p(day)
    out, err, status = Open3.capture3("ruby", CLI, day)
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/not an intent directory/, err)
  end

  def test_cli_prints_screen_for_fixture_intent
    root = tier_root(:project, slug: "demo")
    dir = make_intent(root, title: "Demo intent", checklist: checklist_with(total: 4, done: 1), savepoint: HOW_LEDGER)
    out, err, status = Open3.capture3("ruby", CLI, dir)
    assert_equal 0, status.exitstatus, err
    assert_equal "## ▶ 12 · Demo intent", out.lines.first.strip
    assert_includes out, "| **Progress** | #{'█' * 5}#{'░' * 15} 1 / 4 | 3 steps open |"
    assert_includes out, "| S4 | open | do thing 4 |"
  end
end
