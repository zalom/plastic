require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/intent_screen_ansi"

# Intent 316a, O2: IntentScreenAnsi renders the same record intent_screen.rb
# does, through a truecolor ANSI layout instead of a Markdown table. It calls
# only IntentScreen's public field methods and re-derives nothing (D3), so
# every value but the progress bar must appear, verbatim, in the plain
# render too.
class IntentScreenAnsiTest < Minitest::Test
  HOW_LEDGER = "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze

  def setup
    @home = Dir.mktmpdir("intent-screen-ansi")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def tier_root(slug: "demo")
    root = File.join(@home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, id, title)
    File.write(File.join(root, "INDEX.md"), <<~MD)
      # Index

      ## Active
      - [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags, summary
      ## Future
      ## Completed
      ## Abandoned
    MD
  end

  def make_intent(root, id: "12", title: "Demo intent", checklist: nil, savepoint: nil, insights: [])
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    write_index(root, id, title)
    body = +"---\nid: #{id}\nintent: \"A long intent sentence\"\n"
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

  def plain_render(dir, root)
    template = File.read(File.expand_path("../templates/intent-screen.md", __dir__))
    IntentScreen.render(intent_dir: dir, store_root: root, template: template)
  end

  def ansi_render(dir, root, **opts)
    IntentScreenAnsi.render(intent_dir: dir, store_root: root, **opts)
  end

  def visible(text)
    text.gsub(/\e\[[0-9;]*m/, "")
  end

  # --- matrix 12/13: field reuse, bar excepted ---------------------------------

  def test_every_value_except_the_bar_appears_in_the_plain_render
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 4, done: 1), savepoint: HOW_LEDGER,
                       insights: ["2026-08-30T12:10:02Z · Exec · orchestrator (direct) — Codex re-synced to alpha.2; both harnesses share the 2.0 core."])
    plain = plain_render(dir, root)
    ansi = visible(ansi_render(dir, root, color: false))

    assert_includes plain, "project:demo"
    assert_includes ansi, "project:demo"
    assert_includes plain, "Codex re-synced to alpha.2"
    assert_includes ansi, "Codex re-synced to alpha.2"
    assert_includes plain, "do thing 4"
    assert_includes ansi, "do thing 4"
    assert_includes plain, "Demo intent"
    assert_includes ansi, "Demo intent"
  end

  def test_bar_is_20_cells_plain_and_24_eighths_ansi_with_matching_counts
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 4, done: 1), savepoint: HOW_LEDGER)
    plain = plain_render(dir, root)
    ansi = ansi_render(dir, root, color: false)

    assert_includes plain, "#{'█' * 5}#{'░' * 15} 1 / 4"
    assert_includes ansi, "#{'#' * 6}#{'.' * 18}  1 / 4"
    refute_includes ansi, "#{'█' * 5}#{'░' * 15}" # not the plain 20-cell bar
  end

  # --- matrix 14: palette, no dim ----------------------------------------------

  def test_palette_exact_truecolor_no_dim
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: true)

    assert_includes out, "\e[38;2;45;212;191m"  # teal
    assert_includes out, "\e[38;2;245;158;11m"  # amber
    assert_includes out, "\e[48;2;31;41;55m"    # graphite bg
    assert_includes out, "\e[38;2;148;163;184m" # mid-grey
    assert_includes out, "\e[38;2;243;244;246m" # near-white
    assert_includes out, "\e[1m"                # bold
    refute_includes out, "\e[2m"                # never SGR 2 dim
  end

  # --- matrix 15: bar values ----------------------------------------------------

  def test_bar_values_at_zero_partial_and_full
    root = tier_root
    zero_dir = make_intent(root, id: "20", checklist: checklist_with(total: 4, done: 0), savepoint: HOW_LEDGER)
    full_dir = make_intent(root, id: "21", checklist: checklist_with(total: 4, done: 4), savepoint: HOW_LEDGER)
    partial_dir = make_intent(root, id: "22", checklist: checklist_with(total: 4, done: 2), savepoint: HOW_LEDGER)

    zero = ansi_render(zero_dir, root, color: false)
    full = ansi_render(full_dir, root, color: false)
    partial = ansi_render(partial_dir, root, color: false)

    assert_includes zero, "#{'.' * 24}  0 / 4"
    assert_includes full, "#{'#' * 24}  4 / 4"
    assert_includes partial, "#{'#' * 12}#{'.' * 12}  2 / 4"
  end

  # --- matrix 16: frozen constants, no mutation across calls -------------------

  def test_rendering_twice_does_not_mutate_the_palette_constants
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 3, done: 1), savepoint: HOW_LEDGER)
    first = ansi_render(dir, root, color: true)
    second = ansi_render(dir, root, color: true)
    assert_equal first, second
    assert_equal "\e[38;2;45;212;191m", IntentScreenAnsi::TEAL
  end

  # --- matrix 17: badges --------------------------------------------------------

  def test_badges_teal_on_done_amber_on_open
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: true)

    step_row_re = /\A {2}S\d+ {2}\[/ # only a step row starts with "  S<n>  [" — an
    # escape-code-laden field row (e.g. "Next") never does, even though its own
    # bold/color codes happen to contain literal "[" bytes.
    done_line = out.lines.find { |l| l =~ step_row_re && l.include?("do thing 1") }
    open_line = out.lines.find { |l| l =~ step_row_re && l.include?("do thing 2") }
    refute_nil done_line
    refute_nil open_line
    assert_includes done_line, "\e[38;2;45;212;191m\e[1m done \e[0m"
    assert_includes open_line, "\e[38;2;245;158;11m\e[1m open \e[0m"
  end

  # --- matrix 18: width cap -----------------------------------------------------

  def test_no_line_exceeds_the_width_cap
    root = tier_root
    long_step = (["stepword"] * 30).join(" ")
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - #{long_step}\n"
    long_note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — " + (["clausewordthatisquitelong"] * 20).join(" ") + "."
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER, insights: [long_note])
    out = ansi_render(dir, root, color: true, width: 100)

    out.lines.each do |line|
      vis = visible(line.chomp)
      assert vis.length <= 100, "line exceeded 100 visible columns (#{vis.length}): #{vis.inspect}"
    end
  end

  # --- matrix 19: color:false emits no escape bytes -----------------------------

  def test_color_false_emits_no_escape_bytes
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1), savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: false)
    refute_includes out, "\e"
  end

  # --- matrix 19b: markdown noise stripped (S1 answer 5, live capture) ---------

  def test_backticks_and_asterisks_never_reach_the_block
    root = tier_root
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - see `scripts/lib/intent_screen.rb` and **bold** text\n"
    note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — uses `backtick_path` and **also bold** here."
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER, insights: [note])
    out = ansi_render(dir, root, color: true)

    refute_includes out, "`"
    refute_includes out, "*"
    assert_includes out, "scripts/lib/intent_screen.rb"
    assert_includes out, "bold text"
  end

  # --- matrix 9: shared step-text helper (D3) -----------------------------------

  def test_step_text_in_ansi_matches_step_text_helper_for_the_same_fixture
    root = tier_root
    # Long enough to exercise a real trim (well over STEP_TEXT_MAX=110 would
    # trigger IntentScreen.step_text's own truncation) but still short enough
    # to clear the ANSI width budget untouched, so the two truncations don't
    # stack and mask whether the SAME helper produced both.
    medium_step = (["stepword"] * 8).join(" ") # 71 characters
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - #{medium_step}\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: false)
    plain = plain_render(dir, root)

    expected = IntentScreen.step_text(medium_step)
    assert_equal medium_step, expected # sanity: no truncation at this length
    step_line = out.lines.find { |l| l.include?("[") && l.include?("stepword") }
    refute_nil step_line
    assert_includes step_line, expected
    assert_includes plain, expected
  end

  # --- matrix 10: no escaped pipes leak into the ANSI block ---------------------

  def test_no_escaped_pipe_leaks_into_the_ansi_block
    root = tier_root
    note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — a table cell with a | pipe in it."
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0), savepoint: HOW_LEDGER, insights: [note])
    out = ansi_render(dir, root, color: false)
    refute_includes out, "\\|"
    assert_includes out, "a table cell with a | pipe in it"
  end
end
