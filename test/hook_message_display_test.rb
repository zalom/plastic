require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"
require "open3"
require_relative "../scripts/lib/message_display"
require_relative "../scripts/lib/intent_screen"

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

  def build_project_store(slug: "demo")
    root = File.join(plastic_home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    write_index(root)
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

  def test_chunk_zero_with_prose_before_the_heading_passes_through
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "Sure — here's the state.\n\n## ▶ 50 · Demo"))
    assert_nil out
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
    # every later chunk of this message also passes through: no buffer exists
    out2 = h.handle(payload(index: 1, final: false, delta: " intent\n\nmore text"))
    assert_nil out2
  end

  def test_bare_hash_first_chunk_is_undecided_and_never_engages
    root = build_global_store
    make_intent(root)
    h = handler(root)
    out = h.handle(payload(index: 0, final: false, delta: "#"))
    assert_nil out
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
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

  def test_render_raise_at_final_returns_the_buffered_original
    root = build_global_store
    # "99--broken" exists as a directory but carries no "99--broken.md" —
    # File.read inside IntentScreenAnsi.render raises, which finalize must
    # rescue by returning the buffered original, never nil, never "".
    FileUtils.mkdir_p(File.join(root, "store", "99--broken"))
    h = handler(root)
    buffered = "## ▶ 99 · Broken thing\nsome streamed text\n"

    h.handle(payload(index: 0, final: false, delta: buffered[0, 10]))
    out = h.handle(payload(index: 1, final: true, delta: buffered[10..-1]))
    assert_equal buffered, out
    refute File.exist?(MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "s1", message_id: "m1"))
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

    h = handler(plastic_home)
    h.handle(payload(index: 0, final: false, cwd: File.join(project, "somewhere"), delta: buffered[0, 12]))
    out = h.handle(payload(index: 1, final: true, cwd: File.join(project, "somewhere"), delta: buffered[12..-1]))

    assert_includes out, "\e[1m"
    assert_includes out, "project:demo"
  end

  def test_ambiguous_id_with_no_cwd_match_passes_through
    build_global_store
    make_intent(plastic_home, id: "50", title: "Global fifty")
    project = build_project_store
    make_intent(project, id: "50", title: "Project fifty")
    buffered = "## ▶ 50 · Whatever the model wrote\nsome text\n"

    h = handler(plastic_home)
    h.handle(payload(index: 0, final: false, cwd: "/nowhere/related", delta: buffered[0, 12]))
    out = h.handle(payload(index: 1, final: true, cwd: "/nowhere/related", delta: buffered[12..-1]))

    assert_equal buffered, out
  end

  # --- matrix 37: no fork on the common path (source assertions) ------------

  def test_launcher_source_forks_nothing_on_the_common_path
    src = File.read(LAUNCHER)
    refute_includes src, "$("
    refute_includes src, "`"
    refute_match(/\bsed\b/, src)
    refute_match(/\bjq\b/, src)
    refute_match(/\bcat\b/, src)
    refute_includes src, 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"'
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

    delta = "## ▶ 50 · Demo intent"
    tight = JSON.generate("message_id" => "m1", "session_id" => "s1", "index" => 0,
                           "final" => false, "delta" => delta, "cwd" => root)
    spaced = tight.gsub('":"', '": "').gsub('":0', '": 0').gsub('":false', '": false')

    [tight, spaced].each do |json|
      out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER, stdin_data: json)
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

    path = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "sX", message_id: "mY")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "## ▶ 50 · Demo intent\n")

    # index > 0, an ordinary (non-#) delta: the ONLY way the launcher hands
    # off is by finding a buffer at the path IT computed. If that path ever
    # disagreed with Ruby's own formula, this would hand off to nothing (ruby
    # would also miss its own buffer) and stdout would stay empty.
    out, status = Open3.capture2(
      { "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER,
      stdin_data: JSON.generate("message_id" => "mY", "session_id" => "sX", "index" => 1,
                                 "final" => false, "delta" => "more streamed text", "cwd" => @home),
    )
    assert_equal 0, status.exitstatus
    assert_includes out, '"displayContent":""'
  end

  # --- matrix 41: stdin may arrive in more than one underlying read ---------

  def test_launcher_handles_a_large_payload
    root = build_global_store
    make_intent(root)
    big_tail = "x" * 200_000
    delta = "## ▶ 50 · Demo intent\n\n#{big_tail}"
    json = JSON.generate("message_id" => "big1", "session_id" => "bigsess", "index" => 0,
                          "final" => false, "delta" => delta, "cwd" => root)

    out, status = Open3.capture2({ "PLASTIC_TMP" => @tmp }, "bash", LAUNCHER, stdin_data: json)
    assert_equal 0, status.exitstatus
    assert_includes out, '"displayContent":""'

    buffer = MessageDisplay.buffer_path(tmp_root: @tmp, session_id: "bigsess", message_id: "big1")
    assert File.exist?(buffer)
    assert_equal delta.bytesize, File.read(buffer).bytesize,
      "the full payload must reach the buffer, not a truncated read"
  end
end
