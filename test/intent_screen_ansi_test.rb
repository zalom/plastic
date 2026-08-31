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

  # T2: the expected set is DERIVED from IntentScreen's own field methods,
  # not four hand-picked literals — a hand-picked set can happen to dodge
  # every value that would actually catch a real reuse defect.
  def test_every_value_except_the_bar_appears_in_the_plain_render
    root = tier_root
    insight_line = "2026-08-30T12:10:02Z · Exec · orchestrator (direct) — Codex re-synced to alpha.2; both harnesses share the 2.0 core."
    dir = make_intent(root, checklist: checklist_with(total: 4, done: 1), savepoint: HOW_LEDGER,
                       insights: [insight_line])
    plain = plain_render(dir, root)
    ansi = visible(ansi_render(dir, root, color: false))

    id = File.basename(dir).split("--", 2).first
    intent_text = File.read(File.join(dir, "#{File.basename(dir)}.md"))
    status, title = IntentScreen.index_fields(root, id)
    items = IntentScreen.checklist_items(dir)

    fields = {}
    fields.merge!(IntentScreen.store_fields(root))
    fields["status"] = status
    fields["name"] = title || IntentScreen.fallback_name(intent_text)
    fields.merge!(IntentScreen.savepoint_fields(dir, intent_text))
    fields.merge!(IntentScreen.next_fields(items, status, checklist_present: IntentScreen.items_present?(dir), escape_pipes: false))
    fields.merge!(IntentScreen.insight_fields(intent_text, escape_pipes: false))
    fields["last_step_text"] = IntentScreen.step_text(items.last[:text])

    values = fields.values.map(&:to_s).reject(&:empty?)
    refute_empty values

    values.each do |value|
      assert_includes plain, value, "expected the plain render to include #{value.inspect}"
      assert_includes ansi, value, "expected the ansi render to include #{value.inspect}"
    end
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

  # T3: the bar that actually ships (color: true) had no cell-count
  # assertion at all -- both tests above run color: false and only exercise
  # the ASCII fallback, leaving render_bar's coloured branch (the divmod(8),
  # EIGHTHS[rem], the clamp, the track arithmetic) unexercised.
  def test_render_bar_coloured_branch_has_24_visible_cells_and_the_right_partial_glyph
    out = IntentScreenAnsi.render_bar(1, 7, true) # 27/192 units -> divmod(8) == [3, 3]
    bar = visible(out)
    assert_equal 24, bar.length
    assert_equal "#{'█' * 3}▍#{' ' * 20}", bar
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

  # --- lead's B2: step label padded so the badge column aligns past S9 --------

  def test_step_label_padded_so_the_badge_column_aligns_at_ten_or_more_steps
    root = tier_root
    dir = make_intent(root, checklist: checklist_with(total: 12, done: 3), savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: false)

    step_lines = out.lines.select { |l| l =~ /\A {2}S\d+/ }
    assert_equal 12, step_lines.length
    badge_columns = step_lines.map { |l| l.index("[") }
    assert_equal [badge_columns.first] * badge_columns.length, badge_columns,
      "expected every step row's badge to start at the same column: #{badge_columns.inspect}"
  end

  # --- matrix 18: width cap -----------------------------------------------------

  # markdown_safe: false (matrix 7, intent 316a1): with stripping off, values
  # carrying backticks and `**` are longer than their stripped form, so the
  # cap must still hold on the raw, un-stripped text.
  def test_no_line_exceeds_the_width_cap
    root = tier_root
    long_step = (["`stepword`", "**bold**"] * 15).join(" ")
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - #{long_step}\n"
    long_note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — " + (["`clauseword`", "**thatisquitelong**"] * 10).join(" ") + "."
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER, insights: [long_note])
    out = ansi_render(dir, root, color: true, width: 100, markdown_safe: false)

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

  # --- matrix 1/2/3/6: markdown_safe: default false, conditional clean, both
  # call sites (field value AND step text), split from the pre-316a1 single
  # test that asserted stripping unconditionally (intent 316a1, O1) ----------

  def test_markdown_safe_true_strips_backticks_and_asterisks_at_both_call_sites
    root = tier_root
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - see `scripts/lib/intent_screen.rb` and **bold** text\n"
    note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — uses `backtick_path` and **also bold** here."
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER, insights: [note])
    out = ansi_render(dir, root, color: true, markdown_safe: true)

    refute_includes out, "`"
    refute_includes out, "*"
    assert_includes out, "scripts/lib/intent_screen.rb"
    assert_includes out, "bold text"
  end

  def test_markdown_safe_default_false_leaves_backticks_and_asterisks_intact_at_both_call_sites
    root = tier_root
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - see `scripts/lib/intent_screen.rb` and **bold** text\n"
    note = "2026-08-30T20:51:18Z · Exec · orchestrator (direct) — uses `backtick_path` and **also bold** here."
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER, insights: [note])
    out = ansi_render(dir, root, color: true)

    # The Next field's value is the SAME step text ("...intent_screen.rb`
    # and **bold**..."), so an assert_includes against the whole `out`
    # string is satisfied by the Next row alone even if the Steps section's
    # OWN call site (a separate `clean` call, see intent_screen_ansi.rb) were
    # wrongly cleaning unconditionally. Isolate the "S1" row itself so this
    # pin actually exercises the step-text call site, not just the field
    # row that happens to carry the same text.
    step_line = out.lines.find { |line| line =~ /^\s*S1\b/ }
    refute_nil step_line, "expected an S1 step row in the rendered output"
    assert_includes step_line, "`scripts/lib/intent_screen.rb`"
    assert_includes step_line, "**bold**"

    assert_includes out, "`backtick_path`"
    assert_includes out, "**also bold**"
  end

  # --- matrix 9: shared step-text helper (D3) -----------------------------------

  def test_step_text_in_ansi_matches_step_text_helper_for_the_same_fixture
    root = tier_root
    # T1: over STEP_TEXT_MAX=110 so IntentScreen.step_text ACTUALLY trims —
    # at 71 characters (the old fixture) step_text is the identity function,
    # so the assertion below would stay green even with the shared-helper
    # call deleted from the renderer entirely. A generous `width:` keeps the
    # ANSI renderer's OWN width cap from firing a second time on top, so the
    # two truncations can't stack and mask which one produced the result.
    long_step = (["stepword"] * 20).join(" ") # 179 characters, well over 110
    cl = "# Checklist\n\n## In Progress\n- [ ] Step 1 - #{long_step}\n"
    dir = make_intent(root, checklist: cl, savepoint: HOW_LEDGER)
    out = ansi_render(dir, root, color: false, width: 300)
    plain = plain_render(dir, root)

    expected = IntentScreen.step_text(long_step)
    refute_equal long_step, expected # sanity: a real trim actually happened
    step_line = out.lines.find { |l| l.include?("[") && l.include?("stepword") }
    refute_nil step_line
    assert_equal "  S1  [ open ]  #{expected}\n", step_line
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
