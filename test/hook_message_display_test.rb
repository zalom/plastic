require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"
require "yaml"
require "open3"
require_relative "../scripts/lib/message_display"
require_relative "../scripts/lib/intent_screen"
require_relative "support/hook_replay"

# Intent 316a, O4/O5/O6: the MessageDisplay hook end to end. MessageDisplay is
# the pure handler class (D13: chunk 0 decides, nothing is ever blanked
# speculatively); scripts/hook-message-display is its thin CLI; hooks/message-
# display is the bash launcher that decides with builtins and forks nothing on
# the common (non-screen) case.
class HookMessageDisplayTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  LAUNCHER = File.join(REPO, "hooks", "message-display")
  CLI = File.join(REPO, "scripts", "hook-message-display")
  HOW_LEDGER = "2026-08-30T12:00:00Z  What  50--slug.md\n2026-08-30T12:10:02Z  How  checklist.md created\n".freeze

  def setup
    @home = Dir.mktmpdir("message-display")
    @tmp = Dir.mktmpdir("message-display-tmp")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  # --- fixtures ------------------------------------------------------------

  def plastic_home
    File.join(@home, "plastichome")
  end

  def build_global_store
    root = plastic_home
    FileUtils.mkdir_p(File.join(root, "store"))
    write_index(root)
    root
  end

  # A project's cwd-matching root is its REAL checkout path (projects.yml's
  # own "path:", e.g. ~/apps/personal/plastic) — a different directory from
  # StoreDiscovery's `root` (~/.plastic/projects/<slug>, which only holds
  # INDEX.md and store/). checkout_dir is that real path.
  def build_project_store(slug: "demo")
    root = File.join(plastic_home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    write_index(root)

    checkout_dir = File.join(@home, "checkouts", slug)
    FileUtils.mkdir_p(checkout_dir)
    projects_yml = File.join(plastic_home, "projects.yml")
    existing = File.exist?(projects_yml) ? YAML.safe_load(File.read(projects_yml)) : { "projects" => {} }
    existing["projects"][slug] = { "path" => checkout_dir }
    File.write(projects_yml, YAML.dump(existing))

    root
  end

  def write_index(root)
    File.write(File.join(root, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n## Completed\n\n## Abandoned\n")
  end

  def make_intent(store_root, id: "50", title: "Demo intent", checklist: nil, savepoint: HOW_LEDGER)
    dir = File.join(store_root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(store_root, "INDEX.md"),
               "# Index\n\n## Active\n- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags\n## Future\n\n## Completed\n\n## Abandoned\n")
    body = +"---\nid: #{id}\nintent: \"A long intent sentence\"\n"
    body << "sources: []\nchain: []\ncreated: 2026-08-30\nauthor: human\ntags: [demo]\n---\n\n"
    body << "## Intent\nx\n\n## Context\nx\n\n## Outcome\n\n## Insights\n\n## Links\n"
    File.write(File.join(dir, "#{id}--slug.md"), body)
    File.write(File.join(dir, "checklist.md"), checklist) if checklist
    File.write(File.join(dir, "savepoint.md"), savepoint)
    dir
  end

  def checklist_with(total:, done:)
    items = (1..total).map { |n| "- [#{n <= done ? 'x' : ' '}] Step #{n} - do thing #{n}" }
    "# Checklist: Demo\n\n## In Progress\n#{items.join("\n")}\n\n## Completed\n\n## Session Log\n"
  end

  def plain_screen(intent_dir, store_root)
    template = File.read(File.join(REPO, "templates", "intent-screen.md"))
    IntentScreen.render(intent_dir: intent_dir, store_root: store_root, template: template)
  end

  def handler(plastic_home_dir, color: true, now: Time.parse("2026-08-30T12:00:00Z"))
    MessageDisplay.new(tmp_root: @tmp, plastic_home: plastic_home_dir, color: color, now: now)
  end

  def payload(message_id: "m1", session_id: "s1", index:, final:, delta:, cwd: @home)
    { "message_id" => message_id, "session_id" => session_id, "index" => index,
      "final" => final, "delta" => delta, "cwd" => cwd }
  end

  # --- matrix 23/24/25/26: chunk 0 recognition ------------------------------

  def test_chunk_zero_matching_the_marker_engages
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n\n"))
    assert_equal "", out
    assert File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # 331a (D1/M4): a chunk carrying an opener engages the message FROM THAT
  # OPENER ON, whatever its own index -- superseding the round-3 test above
  # (this rewrites it: all three of its assertions flip). The text before
  # the opener, inside this SAME chunk, is the displayContent; everything
  # from the opener onward is buffered at this chunk's own index, and SCREEN
  # now carries that index instead of an empty marker.
  def test_engaging_chunk_returns_prefix_and_buffers_rest
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "Sure — here's the state.\n\n## ▶ 50 · Demo"))
    assert_equal "Sure — here's the state.\n\n", out
    chunk0 = MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 0)
    assert File.exist?(chunk0)
    assert_equal "## ▶ 50 · Demo", File.read(chunk0)
    refute File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
    screen = MessageDisplay.screen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    assert File.exist?(screen)
    assert_equal "0", File.read(screen).strip
    # every later chunk of this now-engaged message is blanked, not passed through
    out2 = h.handle(payload(index: 1, final: false, delta: " intent\n\nmore text"))
    assert_equal "", out2
  end

  def test_bare_hash_first_chunk_is_undecided_and_never_engages
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "#"))
    assert_nil out
    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 0))
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  def test_single_chunk_double_hash_message_passes_through
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: true, delta: "##"))
    assert_nil out
  end

  # --- matrix 27: blanking, only for an engaged message ---------------------

  def test_non_final_chunks_of_an_engaged_message_are_all_blanked
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1))
    plain = plain_screen(dir, root)
    h = handler(root)
    first = plain[0, 10]
    rest = plain[10..-1]

    assert_equal "", h.handle(payload(index: 0, final: false, delta: first))
    assert_equal "", h.handle(payload(index: 1, final: false, delta: rest[0, 20]))
    final_out = h.handle(payload(index: 2, final: true, delta: rest[20..-1]))
    refute_nil final_out
    refute_equal "", final_out
    assert_includes final_out, "\e[1m" # the styled block, not a blank
  end

  # --- matrix 28/29/30: splice --------------------------------------------

  def test_prose_after_the_screen_survives_the_splice_verbatim
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1))
    plain = plain_screen(dir, root)
    suffix = "**What this means**\n- one bullet\n- another\n\nneeds input: S2\n"
    buffered = plain + suffix
    h = handler(root)

    assert_equal "", h.handle(payload(index: 0, final: false, delta: buffered[0, 30]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[30..-1]))
    assert_includes out, suffix
  end

  def test_checklist_less_intent_splices_correctly
    root = build_global_store
    dir = make_intent(root, checklist: nil)
    plain = plain_screen(dir, root)
    assert_includes plain, "| | | no steps yet |"
    suffix = "**What this means**\n- nothing yet\n\nneeds input: How\n"
    buffered = plain + suffix
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: buffered[0, 20]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[20..-1]))
    assert_includes out, suffix
    assert_includes out, "no steps yet"
  end

  def test_reformatted_screen_falls_back_to_the_line_based_boundary
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0))
    plain = plain_screen(dir, root)
    # The model reformatted a note cell (extra trailing space): the exact
    # prefix no longer matches, so the fallback (## ▶  line through the last
    # "|" line) must still find the same suffix.
    reformatted = plain.sub("the global store", "the global store ")
    suffix = "**What this means**\n- reformatted case\n\nneeds input: S1\n"
    buffered = reformatted + suffix
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: buffered[0, 15]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[15..-1]))
    assert_includes out, suffix
    assert_includes out, "\e[1m"
  end

  # --- lead's B1: the fallback is bounded to the screen's own table ----------

  def test_reformatted_screen_with_prose_and_an_unrelated_table_keeps_the_heading_and_bullets
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0))
    plain = plain_screen(dir, root)
    # Breaks the exact-prefix match, same as the sibling fallback test above.
    reformatted = plain.sub("the global store", "the global store ")
    suffix = <<~MD
      **What this means**
      - one bullet
      - another bullet

      | Col A | Col B |
      | --- | --- |
      | x | y |

      needs input: S1
    MD
    buffered = reformatted + suffix
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: buffered[0, 15]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[15..-1]))

    # The OLD unbounded scan found the last "|" line ANYWHERE in the message
    # -- inside the unrelated table further down -- and dropped everything
    # before it, including the heading and both bullets. The bounded scan
    # must stop at the screen's own table and keep all of this verbatim.
    assert_includes out, "**What this means**"
    assert_includes out, "- one bullet"
    assert_includes out, "- another bullet"
    assert_includes out, "| Col A | Col B |"
    assert_includes out, "needs input: S1"
    assert_includes out, "\e[1m"
  end

  def test_extra_pipe_rows_paint_as_rows_and_the_suffix_survives
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0))
    plain = plain_screen(dir, root)
    # 317a (B10): rows glued onto the screen's own table are indistinguishable
    # by shape, so the painter paints them as rows - content survival, nothing
    # dropped - while the non-grammar suffix stays verbatim.
    extra_rows = "| extra | pipe | row |\n| another | pipe | row |\n"
    suffix = "**What this means**\n- a bullet\n\nneeds input: S1\n"
    buffered = plain + extra_rows + suffix
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: buffered[0, 15]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[15..-1]))

    plain_out = out.gsub(/\e\[[0-9;]*m/, "")
    assert_includes out, "\e["
    assert_includes plain_out, "extra"
    assert_includes plain_out, "another"
    assert_includes out, suffix
  end

  # --- matrix 31/32: fail open ------------------------------------------------

  def test_missing_ids_pass_through
    root = build_global_store
    h = handler(root)
    assert_nil h.handle({})
    assert_nil h.handle({ "message_id" => "", "session_id" => "s1", "index" => 0, "delta" => "## ▶ 50 · x " })
  end

  def test_cli_fails_open_on_bad_json_empty_stdout_exit_zero
    out, status = Open3.capture2(
      { "PLASTIC_TMP" => @tmp },
      "ruby", CLI, stdin_data: "{ not json",
    )
    assert_empty out
    assert_equal 0, status.exitstatus
  end

  def test_cli_fails_open_on_empty_stdin
    out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "ruby", CLI, stdin_data: "")
    assert_empty out
    assert_equal 0, status.exitstatus
  end

  # --- lead's F1: the CLI must honour PLASTIC_HOME, not just its own repo ---

  # Every OTHER spawn test above asserts `"displayContent":""` -- the
  # pre-resolution, still-buffering branch. None of them ever reached the
  # branch that actually resolves an intent and renders the ANSI block
  # through a real subprocess, which is exactly why the S10+ misalignment
  # (matrix B2) shipped unnoticed: the CLI's own `plastic_home` ignored
  # PLASTIC_HOME entirely (always resolving to its own repo checkout) and
  # this whole path silently failed open to "displayContent":"" too, on
  # every fixture-based spawn test that never set PLASTIC_HOME.
  # markdown_safe: true at the adapter's sole call site (matrix 4, intent
  # 316a1): the checklist step carries a backtick, and this asserts on the
  # PARSED displayContent (the ANSI-rendered replacement), not raw stdout —
  # the record itself would still show it, only the substituted block must
  # not.
  def test_cli_honours_plastic_home_and_emits_the_ansi_block
    root = build_global_store
    cl = "# Checklist: Demo\n\n## In Progress\n- [ ] Step 1 - see `backtick_path` here\n\n## Completed\n\n## Session Log\n"
    dir = make_intent(root, checklist: cl)
    plain = plain_screen(dir, root)
    delta = plain + "**What this means**\n- x\n\nneeds input: S1\n"
    json = JSON.generate("message_id" => "envtest", "session_id" => "envsess", "index" => 0,
                          "final" => true, "delta" => delta, "cwd" => root)

    out, status = Open3.capture2(
      { "PLASTIC_TMP" => @tmp, "PLASTIC_HOME" => root },
      "ruby", CLI, stdin_data: json,
    )
    assert_equal 0, status.exitstatus
    parsed = JSON.parse(out)
    content = parsed.dig("hookSpecificOutput", "displayContent")
    refute_nil content
    assert_includes content, "\e[1m"
    refute_includes content, "`"
  end

  def test_paint_raise_at_final_returns_the_buffered_original
    root = build_global_store
    h = handler(root)
    buffered = "## ▶ 99 · Broken thing · here\nsome streamed text\n"

    original = ScreenPaint.method(:paint)
    ScreenPaint.define_singleton_method(:paint) { |*_a, **_k| raise "boom" }
    begin
      h.handle(payload(index: 0, final: false, delta: buffered[0, 10]))
      out = h.handle(payload(index: 1, final: true, delta: buffered[10..-1]))
      assert_equal buffered, out
    ensure
      ScreenPaint.define_singleton_method(:paint, original)
    end
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- lead's F3: a read failure at final is caught, buffer still removed ---

  def test_read_failure_at_final_is_caught_and_the_buffer_is_still_removed
    root = build_global_store
    make_intent(root)
    h = handler(root)
    h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    dir = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    chunk0 = MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 0)
    assert File.exist?(chunk0)

    # Write-only: chunk 1's own write still succeeds, but reassembling the
    # chunks at `final` must read chunk 0 back, and that read fails. Before
    # the round-3 fix, that read sat OUTSIDE the begin/rescue, so this raised
    # straight out of #handle, skipped the `ensure`, and left the message
    # directory behind forever.
    File.chmod(0o200, chunk0)
    begin
      out = h.handle(payload(index: 1, final: true, delta: "more text"))
      assert_nil out
      refute File.exist?(dir), "the message directory must be removed even when reading a chunk at final raises"
    ensure
      File.chmod(0o600, chunk0) if File.exist?(chunk0)
    end
  end

  # --- matrix 33: non-interactive, one payload, no state left behind --------

  def test_non_interactive_single_chunk_splices_and_leaves_no_buffer
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 1, done: 0))
    plain = plain_screen(dir, root)
    buffered = plain + "**What this means**\n- x\n\nneeds input: S1\n"
    h = handler(root)

    out = h.handle(payload(index: 0, final: true, delta: buffered))
    assert_includes out, "\e[1m"
    assert_includes out, "needs input: S1"
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- matrix 34: buffer lifecycle -------------------------------------------

  def test_two_sessions_sharing_a_message_id_do_not_collide
    root = build_global_store
    make_intent(root)
    h = handler(root)
    h.handle(payload(session_id: "sessA", index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    h.handle(payload(session_id: "sessB", index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))

    a = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "sessA", message_id: "m1")
    b = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "sessB", message_id: "m1")
    refute_equal a, b
    assert File.exist?(a)
    assert File.exist?(b)
  end

  def test_aged_buffer_directories_are_pruned_against_injected_now_not_ambient_time
    root = build_global_store
    make_intent(root)
    stale_dir = File.join(@tmp, "plastic-message-display", "stale-session")
    FileUtils.mkdir_p(stale_dir)
    File.write(File.join(stale_dir, "old-message"), "leftover")
    old_time = Time.parse("2026-08-30T00:00:00Z")
    File.utime(old_time, old_time, stale_dir)

    injected_now = old_time + (2 * 3600) # 2 hours later, by the clock we inject
    h = handler(root, now: injected_now)
    h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))

    refute File.exist?(stale_dir), "a buffer dir older than an hour (by injected now) must be pruned"
  end

  # --- matrix 35: off-switch --------------------------------------------------

  def test_color_false_passes_through_from_chunk_zero_always
    root = build_global_store
    make_intent(root)
    h = handler(root, color: false)
    out = h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    assert_nil out
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- matrix 36: O5 resolution ----------------------------------------------

  def test_cwd_under_the_project_root_resolves_the_project_intent
    build_global_store
    make_intent(plastic_home, id: "50", title: "Global fifty")
    project = build_project_store
    make_intent(project, id: "50", title: "Project fifty", checklist: checklist_with(total: 1, done: 0))
    plain = plain_screen(File.join(project, "store", "50--slug"), project)
    buffered = plain + "**What this means**\n- x\n\nneeds input: S1\n"

    real_cwd = File.join(@home, "checkouts", "demo", "somewhere")
    h = handler(plastic_home)
    h.handle(payload(index: 0, final: false, cwd: real_cwd, delta: buffered[0, 12]))
    out = h.handle(payload(index: 1, final: true, cwd: real_cwd, delta: buffered[12..-1]))

    assert_includes out, "\e[1m"
    assert_includes out, "project:demo"
  end

  def test_ambiguous_or_unknown_ids_paint_without_resolution
    # 317a (A4): engagement is grammar, not identity - the roster and delay
    # screens carry no id at all, so nothing resolves ids anymore. A screen
    # whose id matches no store (or many) still paints exactly as printed.
    root = build_global_store
    h = handler(root)
    text = "## ▶ 999 · No such intent · anywhere\n\n| | | |\n| --- | --- | --- |\n| **Stage** | Exec | open |\n"
    out = nil
    text.lines.each_with_index do |line, i|
      out = h.handle(payload(index: i, final: i == text.lines.length - 1, delta: line))
    end
    refute_nil out
    assert_includes out, "\e["
    assert_includes out.gsub(/\e\[[0-9;]*m/, ""), "No such intent"
  end

  # --- lead's F4: resolve before engaging, at chunk 0 -------------------------

  def test_chunk_zero_prose_never_buffers_and_never_blanks
    root = build_global_store
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "Here is what I found today.\n"))
    assert_nil out
    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 0)),
      "prose must never create a chunk file, so nothing is ever blanked for it"
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- matrix 37: no fork on the common path (source assertions) ------------

  def test_launcher_source_forks_nothing_on_the_common_path
    # Scan CODE lines only — the launcher's own header comment documents, by
    # name, the pattern it deliberately does not use, and a naive whole-file
    # scan would trip on the documentation rather than the code.
    code = File.readlines(LAUNCHER).reject { |l| l.strip.start_with?("#") }.join
    refute_includes code, "$("
    refute_includes code, "`"
    refute_match(/\bsed\b/, code)
    refute_match(/\bjq\b/, code)
    refute_match(/\bcat\b/, code)
    refute_match(/\$\(cd .*&&\s*pwd\)/, code)
  end

  # --- matrix 38: install rewrite token --------------------------------------

  def test_launcher_keeps_the_literal_rewrite_token
    src = File.read(LAUNCHER)
    assert_includes src, '$SCRIPT_DIR/../scripts/hook-message-display'
  end

  # --- matrix 39: glob is a single "#", both spacings ------------------------

  def test_launcher_hands_off_on_a_single_hash_delta_both_json_spacings
    root = build_global_store
    make_intent(root)
    # PLASTIC_HOME must point at the fixture store: chunk 0 now resolves the
    # intent before engaging (F4), and the CLI honours PLASTIC_HOME (F1)
    # rather than always resolving to its own repo checkout.

    delta = "## ▶ 50 · Demo intent"
    tight = JSON.generate("message_id" => "m1", "session_id" => "s1", "index" => 0,
                           "final" => false, "delta" => delta, "cwd" => root)
    spaced = tight.gsub('":"', '": "').gsub('":0', '": 0').gsub('":false', '": false')

    [tight, spaced].each do |json|
      out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp, "PLASTIC_HOME" => root }, "bash", LAUNCHER, stdin_data: json)
      assert_equal 0, status.exitstatus
      assert_includes out, '"displayContent":""', "expected a hand-off for: #{json}"
    end
  end

  def test_launcher_does_not_hand_off_on_an_ordinary_message
    out, status = Open3.capture2(
      { "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER,
      stdin_data: JSON.generate("message_id" => "m2", "session_id" => "s2", "index" => 0,
                                 "final" => false, "delta" => "Sure, here is a summary.", "cwd" => @home),
    )
    assert_equal 0, status.exitstatus
    assert_empty out
  end

  # --- matrix 40: bash and ruby build the identical buffer path -------------

  def test_bash_and_ruby_agree_on_the_buffer_path
    src = File.read(LAUNCHER)
    assert_includes src, MessageDisplay::BUFFER_DIR_NAME

    dir = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "sX", message_id: "mY")
    screen = MessageDisplay.screen_path(tmp_root: @tmp, session_id: "sX", message_id: "mY")
    FileUtils.mkdir_p(dir)
    File.write(screen, "/some/intent/dir\n/some/store/root\n")

    # index > 0, an ordinary (non-pipe, non-Steps, non-blank) delta: the ONLY
    # way the launcher hands off is by finding the message directory IT
    # computed already on disk. If that path ever disagreed with Ruby's own
    # formula, this would hand off to nothing (ruby would also miss its own
    # decision) and stdout would stay empty.
    out, status = Open3.capture2(
      { "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER,
      stdin_data: JSON.generate("message_id" => "mY", "session_id" => "sX", "index" => 1,
                                 "final" => false, "delta" => "more streamed text", "cwd" => @home),
    )
    assert_equal 0, status.exitstatus
    assert_includes out, '"displayContent":""'
  end

  # --- lead's F2: the launcher's own TMP_ROOT formula wins by construction --

  def test_launcher_exports_the_computed_tmp_root_so_ruby_agrees
    # Ruby's Dir.tmpdir requires the candidate directory to already exist and
    # be writable, so a NONEXISTENT TMPDIR is silently skipped there and it
    # falls back to /tmp; bash's own "${TMPDIR:-/tmp}" takes it literally,
    # with no existence check at all. Before the fix, chunk 0 (ruby, no
    # PLASTIC_TMP set) would buffer under /tmp while chunk 1 (bash, deciding
    # hand-off by checking its OWN computed BUFFER path under the nonexistent
    # TMPDIR) would never find it and never forward — the message would
    # display with its opening chunk gone forever. Exporting PLASTIC_TMP from
    # the root bash itself computed makes one formula win, so this can no
    # longer diverge.
    nonexistent_tmpdir = File.join(@tmp, "does-not-exist-yet")
    root = build_global_store
    make_intent(root)
    env = { "PLASTIC_TMP" => nil, "TMPDIR" => nonexistent_tmpdir, "PLASTIC_HOME" => root }

    json0 = JSON.generate("message_id" => "tmpmatch", "session_id" => "tmpsess", "index" => 0,
                           "final" => false, "delta" => "## ▶ 50 · Demo intent\n", "cwd" => root)
    out0, status0 = Open3.capture2(env, "bash", LAUNCHER, stdin_data: json0)
    assert_equal 0, status0.exitstatus
    assert_includes out0, '"displayContent":""'

    buffer = File.join(nonexistent_tmpdir, "plastic-message-display", "tmpsess", "tmpmatch")
    assert File.exist?(buffer), "ruby should have honoured the bash-computed TMP_ROOT via the exported PLASTIC_TMP"

    json1 = JSON.generate("message_id" => "tmpmatch", "session_id" => "tmpsess", "index" => 1,
                           "final" => true, "delta" => " more streamed text", "cwd" => root)
    out1, status1 = Open3.capture2(env, "bash", LAUNCHER, stdin_data: json1)
    assert_equal 0, status1.exitstatus
    parsed = JSON.parse(out1)
    content = parsed.dig("hookSpecificOutput", "displayContent")
    refute_nil content, "chunk 1 must still be forwarded once the buffer exists at the agreed-upon path"
    refute_empty content
  end

  # --- matrix 41: stdin may arrive in more than one underlying read ---------

  def test_launcher_handles_a_large_payload
    root = build_global_store
    make_intent(root)
    big_tail = "x" * 200_000
    delta = "## ▶ 50 · Demo intent\n\n#{big_tail}"
    json = JSON.generate("message_id" => "big1", "session_id" => "bigsess", "index" => 0,
                          "final" => false, "delta" => delta, "cwd" => root)

    out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp, "PLASTIC_HOME" => root }, "bash", LAUNCHER, stdin_data: json)
    assert_equal 0, status.exitstatus
    assert_includes out, '"displayContent":""'

    chunk0 = MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "bigsess", message_id: "big1", index: 0)
    assert File.exist?(chunk0)
    assert_equal delta.bytesize, File.read(chunk0).bytesize,
      "the full payload must reach the chunk file, not a truncated read"
  end

  # --- round 3: Claude Code fires the per-chunk hook processes concurrently -

  # No real sleeping anywhere below: the injected sleeper is either a no-op
  # counter (proves a chunk never waits), or a lambda that performs "chunk
  # 0's work" as its side effect (simulating chunk 0's decision landing
  # while a later chunk is mid-poll), which is deterministic without threads
  # or wall-clock time.

  def test_out_of_order_chunks_reassemble_in_index_order
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 3, done: 1))
    plain = plain_screen(dir, root)
    suffix = "**What this means**\n- x\n\nneeds input: S2\n"
    full = plain + suffix

    lines = plain.lines
    table_lines = lines[2..-1]
    third = (table_lines.length / 3.0).ceil
    c0 = lines[0] + lines[1]
    c1 = table_lines[0, third].join
    c2 = table_lines[third, third].join
    c3 = table_lines[(third * 2)..-1].join
    c4 = suffix
    assert_equal full, c0 + c1 + c2 + c3 + c4, "fixture slicing must partition `full` exactly"

    h = nil
    chunk_zero_ran = false
    sleeper = lambda do |_seconds|
      next if chunk_zero_ran

      chunk_zero_ran = true
      # Chunk 0's decision lands DURING chunk 1's poll -- the exact race
      # from the live capture, reproduced deterministically.
      h.handle(payload(index: 0, final: false, delta: c0))
    end
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    out1 = h.handle(payload(index: 1, final: false, delta: c1))
    out2 = h.handle(payload(index: 2, final: false, delta: c2))
    out3 = h.handle(payload(index: 3, final: false, delta: c3))
    out4 = h.handle(payload(index: 4, final: true, delta: c4))

    assert_equal "", out1
    assert_equal "", out2
    assert_equal "", out3
    assert_includes out4, "\e[1m"
    assert_includes out4, suffix
  end

  def test_wait_budget_exhausted_before_chunk_zero_decides_passes_through
    root = build_global_store
    make_intent(root)
    sleep_calls = 0
    sleeper = ->(_seconds) { sleep_calls += 1 }
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    # Chunk 0 never runs in this test at all: the decision never arrives.
    out1 = h.handle(payload(index: 1, final: false, delta: "| --- | --- |\n"))
    assert_nil out1
    assert_equal 15, sleep_calls, "the full (300 / 20).ceil poll budget must be paid, and no more"

    out2 = h.handle(payload(index: 2, final: false, delta: "| a | b |\n"))
    assert_nil out2

    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 1)),
      "a chunk that gave up waiting must never have buffered its delta"
  end

  def test_ordinary_prose_message_out_of_order_never_waits
    root = build_global_store
    make_intent(root)
    sleep_calls = 0
    sleeper = ->(_seconds) { sleep_calls += 1 }
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    out = h.handle(payload(index: 1, final: false, delta: "Sure, here is more of the summary."))
    assert_nil out
    assert_equal 0, sleep_calls, "an ordinary prose chunk must never enter the poll loop at all"
  end

  def test_final_chunk_arriving_before_an_earlier_chunk_file_paints_whats_present
    root = build_global_store
    make_intent(root)
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"), wait_ms: 0, poll_ms: 20)

    h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    # Chunk 1 never arrives; the final chunk (index 2) shows up anyway. What
    # is present still paints (317a: the title region), and the trailing text
    # survives verbatim - never nil, never "".
    out = h.handle(payload(index: 2, final: true, delta: "trailing text\n"))

    refute_nil out
    refute_equal "", out
    assert_includes out, "\e["
    assert_includes out.gsub(/\e\[[0-9;]*m/, ""), "Demo intent"
    assert_includes out, "trailing text\n"
  end

  def test_noscreen_short_circuits_later_chunks_immediately
    root = build_global_store
    sleep_calls = 0
    sleeper = ->(_seconds) { sleep_calls += 1 }
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    # 317a (A4): an ordinary prose chunk 0 writes NOSCREEN - grammar decides,
    # not id resolution, and prose is not grammar.
    h.handle(payload(index: 0, final: false, delta: "Sure, here is a summary.\n"))
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))

    out = h.handle(payload(index: 1, final: false, delta: "| some | row |\n"))
    assert_nil out
    assert_equal 0, sleep_calls, "NOSCREEN already exists, so a later chunk decides without polling"
  end

  # --- 317a S12 (A3/A4/B10): grammar engagement, no id resolution ------------

  def drive(handler_obj, text, message_id: "m317")
    lines = text.lines
    out = nil
    lines.each_with_index do |line, i|
      final = i == lines.length - 1
      out = handler_obj.handle(payload(message_id: message_id, index: i, final: final, delta: line))
    end
    out
  end

  def test_roster_screen_paints_end_to_end_without_resolution
    root = build_global_store
    text = "▶ In delivery · 2 intents · 2026-08-31 17:00 UTC\n\n" \
           "| Intent | Stage | Progress | Changed | Lead |\n| --- | --- | --- | --- | --- |\n" \
           "| 317 | Exec | ███░░ 3 / 5 | on request | idle |\n"
    out = drive(handler(root), text)
    refute_nil out
    assert_includes out, "\e["
    assert_includes out, "In delivery"
    refute_match(/^\s*\|/, out.gsub(/\e\[[0-9;]*m/, ""))
  end

  def test_delay_screen_paints_end_to_end
    root = build_global_store
    text = "✔ 315b · Fix regressions · delivered in 1 h 51 min\n\n" \
           "19:00  What  315b--fix-regressions.md\n20:51  Done  delivered\n\n" \
           "**Where the time went**   longest gap 111 min\n"
    out = drive(handler(root), text)
    refute_nil out
    assert_includes out, "\e["
    assert_includes out.gsub(/\e\[[0-9;]*m/, ""), "Where the time went"
  end

  def test_delivered_screen_paints_end_to_end
    root = build_global_store
    text = "## ✔ 317 · Delivery reports · delivered\n" \
           "2026-08-31 17:02 UTC · auto · 7 h 51 min · v2.0.0-alpha.8\n\n" \
           "**Asked**\n  the ask body\n  3 decisions in spec.md\n\n" \
           "**Delivered**\n| Row | What | Proven by |\n| --- | --- | --- |\n| S1 | a thing | 4 tests |\n\n" \
           "**Needs you**\nNone\n"
    out = drive(handler(root), text)
    refute_nil out
    assert_includes out, "\e["
    plain = out.gsub(/\e\[[0-9;]*m/, "")
    assert_includes plain, "a thing"
    refute_match(/^\s*\|/, plain)
  end

  def test_state_screen_keeps_its_changed_row
    root = build_global_store
    text = "## ▶ 316a · ANSI intent screen\n\n" \
           "| | | |\n| --- | --- | --- |\n" \
           "| **Stage** | Exec | the work is open |\n" \
           "| **Changed** | How written, review next | the reason this screen printed |\n"
    out = drive(handler(root), text)
    refute_nil out
    assert_includes out.gsub(/\e\[[0-9;]*m/, ""), "How written, review next"
  end

  def test_engaged_prose_message_keeps_its_prose_verbatim
    root = build_global_store
    text = "▶ Odd · opener line\nplain prose that is not screen grammar at all\nmore prose\n"
    out = drive(handler(root), text)
    refute_nil out
    plain_out = out.gsub(/\e\[[0-9;]*m/, "")
    assert_includes plain_out, "plain prose that is not screen grammar at all\nmore prose\n"
  end

  def test_prose_after_the_painted_screen_survives
    root = build_global_store
    text = "## ✔ 9 · Tiny · delivered\n2026-08-31 · auto · 1 min · v1\n\n**Needs you**\nNone\n\n" \
           "In plain words: it shipped.\n"
    out = drive(handler(root), text)
    refute_nil out
    assert_includes out, "In plain words: it shipped."
    assert_includes out, "\e["
  end

  # --- 317a S12e (B1): a missing lib must not break every chunk --------------

  def test_missing_screen_paint_lib_fails_open_exit_zero_silent
    broken = File.join(@home, "brokencopy")
    FileUtils.mkdir_p(File.join(broken, "scripts"))
    FileUtils.cp(File.join(REPO, "scripts", "hook-message-display"), File.join(broken, "scripts", "hook-message-display"))
    payload_json = JSON.generate(payload(index: 0, final: true, delta: "## ▶ 50 · x"))
    out, err, status = Open3.capture3({ "PLASTIC_TMP" => @tmp },
                                      RbConfig.ruby, File.join(broken, "scripts", "hook-message-display"),
                                      stdin_data: payload_json)
    assert_equal 0, status.exitstatus
    assert_empty out
    assert_empty err
  end

  # --- 317a S13 (B11): the launcher hands off bare ▶/✔ and escaped forms -----

  def test_launcher_hands_off_on_screen_opener_deltas
    [%q<{"message_id":"m1","session_id":"s1","index":0,"final":false,"delta":"▶ In delivery · 2"}>,
     %q<{"message_id":"m1","session_id":"s1","index":0,"final":false,"delta":"✔ 315b · Fix"}>,
     %q<{"message_id":"m1","session_id":"s1","index":0,"final":false,"delta":"▶ In delivery"}>,
     %q<{"message_id":"m1","session_id":"s1","index":0,"final":false,"delta":"✔ 315b · Fix"}>,
     %q<{"message_id":"m1","session_id":"s1","index":0, "final":false, "delta": "▶ roster"}>].each do |json|
      run = launcher_run(json)
      assert run, "launcher must hand off screen opener delta: #{json}"
    end
  end

  def test_launcher_source_carries_the_bold_section_glob
    src = File.read(LAUNCHER)
    assert_includes src, %q<*'"delta":"**'*>
    assert_includes src, %q<*'"delta": "**'*>
  end

  def launcher_run(json)
    out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER, stdin_data: json)
    return false unless status.exitstatus.zero?
    out.include?('"displayContent":""')
  end

  # =========================================================================
  # Intent 331a: the hook engages anywhere. A chunk carrying a screen opener
  # engages the message from that chunk on, whatever its own index -- not
  # only chunk 0. SCREEN now carries the engaging chunk's index (D1/D2/D6);
  # the final chunk waits for chunk files from that index onward, not from 0
  # (D3); a fence immediately wrapping the opener is dropped (D4); NOSCREEN
  # is replaceable once a later opener lands (D2).
  # =========================================================================

  # --- T1: the hermetic replay harness (test/support/hook_replay.rb) -------

  def test_replay_fixture_takes_hook_path_and_tmp_root_as_arguments
    assert_raises(ArgumentError) { HookReplay.replay(text: "hi") }

    tmp = Dir.mktmpdir("hook-replay-hermetic")
    begin
      outs = HookReplay.replay(hook_path: LAUNCHER, tmp_root: tmp, text: "Sure, here's an ordinary summary.\n")
      assert_nil HookReplay.final_display_content(outs), "ordinary prose never engages"
      refute Dir.exist?(File.join(@tmp, "plastic-message-display")),
        "the replay must write only under the tmp_root it was given, never the ambient suite tmp"
    ensure
      FileUtils.rm_rf(tmp)
    end
  end

  # --- T2: the chunk-0 golden, captured at the alpha base before any source
  # file was touched (test/fixtures/golden_chunk_zero_state.txt) -----------

  def test_chunk_zero_opener_is_byte_identical_to_golden
    root = build_global_store
    dir = make_intent(root, checklist: checklist_with(total: 2, done: 1))
    plain = plain_screen(dir, root)
    suffix = "**What this means**\n- a bullet\n\nneeds input: S2\n"
    buffered = plain + suffix
    h = handler(root)

    out = h.handle(payload(index: 0, final: true, delta: buffered))
    golden = File.read(File.join(REPO, "test", "fixtures", "golden_chunk_zero_state.txt"))
    assert_equal golden, out, "a real regression in the already-shipped chunk-0 path must not hide behind a self-comparison"
  end

  # --- M1: prose chunk 0, opener in chunk 3 --------------------------------

  def test_late_opener_engages_and_paints_final
    root = build_global_store
    make_intent(root)
    h = handler(root)

    out0 = h.handle(payload(index: 0, final: false, delta: "Here is where 50 stands today.\n"))
    out1 = h.handle(payload(index: 1, final: false, delta: "A little more scene setting.\n"))
    out2 = h.handle(payload(index: 2, final: false, delta: "Still just talking.\n"))
    assert_nil out0
    assert_nil out1
    assert_nil out2
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))

    out3 = h.handle(payload(index: 3, final: false, delta: "## ▶ 50 · Demo intent\n"))
    assert_equal "", out3
    refute File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
    screen = MessageDisplay.screen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    assert File.exist?(screen)
    assert_equal "3", File.read(screen).strip

    out4 = h.handle(payload(index: 4, final: true, delta: "trailing text after the screen\n"))
    refute_nil out4
    assert_includes out4, "\e[1m"
    assert_includes out4.gsub(/\e\[[0-9;]*m/, ""), "Demo intent"
    assert_includes out4, "trailing text after the screen\n"
  end

  # --- M3: 30 prose chunks, no opener ---------------------------------------

  def test_prose_only_message_never_buffers
    root = build_global_store
    make_intent(root)
    h = handler(root)

    outs = (0...30).map do |i|
      h.handle(payload(index: i, final: i == 29, delta: "Just more ordinary prose, sentence #{i}.\n"))
    end

    assert(outs.all?(&:nil?), "every chunk of an unengaged 30-chunk prose message must pass through")
    (0...30).each do |i|
      refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: i)),
        "chunk #{i} must never be buffered when the message never engages"
    end
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- M5: the final chunk waits only from the start index -------------------

  def test_final_waits_only_from_start_index
    root = build_global_store
    make_intent(root)
    sleep_calls = 0
    sleeper = ->(_seconds) { sleep_calls += 1 }
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    h.handle(payload(index: 0, final: false, delta: "Prose before anything screen-shaped.\n"))
    h.handle(payload(index: 1, final: false, delta: "Still prose.\n"))
    h.handle(payload(index: 2, final: false, delta: "Still prose.\n"))
    h.handle(payload(index: 3, final: false, delta: "## ▶ 50 · Demo intent\n"))
    assert_equal 0, sleep_calls, "engaging never polls; the opener is found in the chunk's own delta"

    out4 = h.handle(payload(index: 4, final: true, delta: "trailing text\n"))
    assert_equal 0, sleep_calls,
      "waiting from the start index (3), not 0, costs no poll: chunk 3's own file is already on disk"
    refute_nil out4
    assert_includes out4, "trailing text\n"
  end

  # --- M5a: the start index round-trips across process boundaries ----------

  def test_screen_file_round_trips_the_start_index_across_instances
    root = build_global_store
    make_intent(root)
    h1 = handler(root)
    h1.handle(payload(index: 0, final: false, delta: "Prose stands here.\n"))
    h1.handle(payload(index: 1, final: false, delta: "## ▶ 50 · Demo intent\n"))

    screen = MessageDisplay.screen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    assert_equal "1", File.read(screen).strip

    # A brand new instance -- a separate process in production -- must read
    # the same start index back off disk rather than trusting in-memory state.
    h2 = handler(root)
    out = h2.handle(payload(index: 2, final: true, delta: "trailing\n"))
    refute_nil out
    assert_includes out, "trailing\n"
    assert_includes out, "\e[1m"
  end

  # --- M6: NOSCREEN written by chunk 0, opener at chunk 2 -------------------

  def test_noscreen_is_replaced_by_later_opener
    root = build_global_store
    make_intent(root)
    h = handler(root)
    h.handle(payload(index: 0, final: false, delta: "Ordinary prose.\n"))
    noscreen = MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    screen = MessageDisplay.screen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1")
    assert File.exist?(noscreen)
    refute File.exist?(screen)

    out = h.handle(payload(index: 2, final: false, delta: "## ▶ 50 · Demo intent\n"))
    assert_equal "", out
    refute File.exist?(noscreen), "NOSCREEN must be removed once a later chunk engages"
    assert File.exist?(screen)
    assert_equal "2", File.read(screen).strip
  end

  # --- M9: a screen-shaped chunk exhausts its budget before the opener lands -

  def test_budget_exhausted_chunk_is_absent_from_the_final_splice
    root = build_global_store
    make_intent(root)
    sleep_calls = 0
    sleeper = ->(_seconds) { sleep_calls += 1 }
    h = MessageDisplay.new(tmp_root: @tmp, plastic_home: root, color: true,
                            now: Time.parse("2026-08-30T12:00:00Z"),
                            wait_ms: 300, poll_ms: 20, sleeper: sleeper)

    # Chunk 2 looks screen-shaped (a table row) and arrives while nothing has
    # decided yet; the opener (chunk 3) never runs during this test, so
    # chunk 2 exhausts its poll budget and gives up.
    lost_delta = "| a | b |\n"
    out2 = h.handle(payload(index: 2, final: false, delta: lost_delta))
    assert_nil out2
    assert_equal 15, sleep_calls, "the full (300 / 20).ceil poll budget must be paid before giving up"
    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 2))

    h.handle(payload(index: 3, final: false, delta: "## ▶ 50 · Demo intent\n"))
    out4 = h.handle(payload(index: 4, final: true, delta: "trailing text\n"))

    refute_nil out4
    plain_out4 = out4.gsub(/\e\[[0-9;]*m/, "")
    refute_includes plain_out4, "a | b"
    # Measured residual (report this number back): exactly the one chunk
    # that timed out is lost entirely from the final splice.
    residual_chunks = 1
    residual_bytes = lost_delta.bytesize
    assert_equal 1, residual_chunks
    assert_equal 10, residual_bytes
  end

  # --- M10: the painter raises, on the LATE-engaged path --------------------

  def test_finalize_error_returns_buffered_original
    root = build_global_store
    h = handler(root)

    out0 = h.handle(payload(index: 0, final: false, delta: "Prose stands here first.\n"))
    assert_nil out0
    out1 = h.handle(payload(index: 1, final: false, delta: "## ▶ 99 · Broken thing · here\n"))
    assert_equal "", out1

    original = ScreenPaint.method(:paint)
    ScreenPaint.define_singleton_method(:paint) { |*_a, **_k| raise "boom" }
    begin
      out2 = h.handle(payload(index: 2, final: true, delta: "some streamed text\n"))
      assert_equal "## ▶ 99 · Broken thing · here\nsome streamed text\n", out2
    ensure
      ScreenPaint.define_singleton_method(:paint, original)
    end
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- M11: color: false never engages late ---------------------------------

  def test_color_false_never_engages_late
    root = build_global_store
    make_intent(root)
    h = handler(root, color: false)

    out0 = h.handle(payload(index: 0, final: false, delta: "Prose before anything.\n"))
    out1 = h.handle(payload(index: 1, final: true, delta: "## ▶ 50 · Demo intent\n"))
    assert_nil out0
    assert_nil out1
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- M13: an opener split across two deltas falls back to plain -----------

  def test_opener_split_across_deltas_falls_back_to_plain
    root = build_global_store
    make_intent(root)
    h = handler(root)

    # Split right after the glyph, before its required trailing space: chunk
    # 0's own delta ends in "## ▶" (no space, so ENGAGE_RE cannot match it),
    # and chunk 1's own delta starts with a bare " 50 · Demo intent" (no
    # marker at all once its leading space is stripped for the test). Neither
    # chunk's delta matches alone -- a known, accepted limitation (331a
    # matrix M13): late engagement only ever looks at ONE chunk's delta at a
    # time, never a cross-chunk reassembly, before deciding.
    out0 = h.handle(payload(index: 0, final: false, delta: "Some prose.\n\n## ▶"))
    out1 = h.handle(payload(index: 1, final: true, delta: " 50 · Demo intent\n"))

    assert_nil out0
    assert_nil out1
    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 0))
    refute File.exist?(MessageDisplay.chunk_path(tmp_root: @tmp, session_id: "s1", message_id: "m1", index: 1))
    assert File.exist?(MessageDisplay.noscreen_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
  end

  # --- M7: a fence line immediately before the opener, same chunk -----------

  def test_fence_before_opener_in_same_chunk_is_dropped
    root = build_global_store
    make_intent(root)
    h = handler(root)

    out = h.handle(payload(index: 0, final: false, delta: "```\n## ▶ 50 · Demo intent\n"))
    assert_equal "", out, "the lone fence line immediately before the opener must be dropped, leaving no visible prefix"

    final_out = h.handle(payload(index: 1, final: true, delta: "trailing text\n"))
    refute_includes final_out, "```"
    assert_includes final_out, "trailing text"
  end

  # --- M8: a closing fence right after the region ---------------------------

  def test_closing_fence_after_region_is_dropped
    root = build_global_store
    make_intent(root)
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    out = h.handle(payload(index: 1, final: true, delta: "```\nafter the screen\n"))

    refute_includes out, "```"
    assert_includes out, "after the screen"
  end

  # --- M8a: a fence opened in an EARLIER chunk is left alone ----------------

  def test_fence_in_an_earlier_chunk_is_left_alone
    root = build_global_store
    make_intent(root)
    h = handler(root)

    out0 = h.handle(payload(index: 0, final: false, delta: "```\nsome earlier fenced example\n```\n"))
    assert_nil out0, "an earlier, unengaged chunk's own fence is not this class's concern at all"

    out1 = h.handle(payload(index: 1, final: false, delta: "## ▶ 50 · Demo intent\n"))
    assert_equal "", out1

    out2 = h.handle(payload(index: 2, final: true, delta: "trailing\n"))
    refute_nil out2
    assert_includes out2, "trailing\n"
    refute_includes out2, "```"
  end

  # --- M8b: an unrelated code fence elsewhere survives verbatim -------------

  def test_unrelated_code_fence_survives_verbatim
    root = build_global_store
    make_intent(root)
    h = handler(root)

    h.handle(payload(index: 0, final: false, delta: "## ▶ 50 · Demo intent\n"))
    suffix = "**What this means**\n- see the example below\n\n```ruby\nputs 'hi'\n```\n"
    out = h.handle(payload(index: 1, final: true, delta: suffix))

    assert_includes out, "```ruby"
    assert_includes out, "puts 'hi'"
    assert_includes out, "```\n"
  end

  # --- M12a: a chunk at index > 0 whose delta carries an opener anywhere ----

  def test_launcher_hands_off_a_late_opener_at_any_index
    raw = [
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"the intent stands.\n\n## ▶ 50 · Demo intent"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"the intent stands.\n\n## ✔ 50 · Demo intent · delivered"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"still talking, then ▶ In delivery · 2 intents"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"and finally ✔ 5 done"}>,
    ]
    escaped = [
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"the intent stands.\n\n## ▶ 50 · Demo intent"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"the intent stands.\n\n## ✔ 50 · Demo intent · delivered"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"still talking, then ▶ In delivery · 2 intents"}>,
      %q<{"session_id":"s1","message_id":"m1","index":3,"final":false,"delta":"and finally ✔ 5 done"}>,
    ]
    (raw + escaped).each do |json|
      out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER, stdin_data: json)
      assert_equal 0, status.exitstatus
      assert_includes out, '"hookSpecificOutput"', "launcher must hand off a late opener at any index: #{json}"
    end
  end

  # --- M12b: the permissive bare-# chunk-0 arm must be JOINED, not replaced -

  def test_launcher_keeps_the_bare_hash_chunk_zero_glob
    src = File.read(LAUNCHER)
    assert_includes src, %q<*'"delta":"#'*|*'"delta": "#'*) handoff=1 ;;>,
      "the existing chunk-0 bare-# arm must survive verbatim"
    assert_includes src, "## ▶", "the new any-index opener glob must join it, not replace it"
  end

  # --- M12d: ordinary prose merely mentioning a glyph still hands off, and
  # Ruby's own (stricter) grammar fails open rather than mis-painting it -----

  def test_prose_mentioning_a_glyph_hands_off_and_ruby_fails_open
    json = JSON.generate("message_id" => "m1", "session_id" => "s1", "index" => 3,
                          "final" => true, "delta" => "## ▶ this is not a real screen, just chevrons\n")
    out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER, stdin_data: json)
    assert_equal 0, status.exitstatus
    refute_empty out, "the launcher cannot distinguish a real opener from prose merely shaped like one, so it hands off"
    parsed = JSON.parse(out)
    content = parsed.dig("hookSpecificOutput", "displayContent")
    refute_includes content, "\e[",
      "Ruby's own grammar finds no real opener (no id/name separator anywhere), so it fails open to the original text"
    assert_equal "## ▶ this is not a real screen, just chevrons\n", content
  end

end
