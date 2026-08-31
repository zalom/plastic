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
    File.write(File.join(@store, "INDEX.md"),
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
    ReportScreen.render_state(intent_dir: @dir, store_root: @store,
                              changed: "test print", template: @state_template)
  end

  # --- content survival on the state screen (matrix S10a/S10b) ---

  def test_state_screen_paints_with_every_value_surviving_and_no_pipes
    painted = ScreenPaint.paint(state_screen, color: true)
    refute_nil painted
    assert_includes painted, ESC
    plain = strip_ansi(painted)
    ["21", "Paint demo", "project:store", "Active", "test print",
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
    out = ReportScreen.render_roster(@store, changed: nil)
    painted = ScreenPaint.paint(out, color: true)
    refute_nil painted
    plain = strip_ansi(painted)
    assert_includes plain, "In delivery"
    assert_includes plain, "21"
    refute_match(/^\s*\|/, plain)
  end

  def test_intent_screen_paints
    template = File.read(File.expand_path("../templates/intent-screen.md", __dir__))
    out = IntentScreen.render(intent_dir: @dir, store_root: @store, template: template)
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
    assert_equal "In plain words, this is prose.\n", lines[stop]
  end
end
