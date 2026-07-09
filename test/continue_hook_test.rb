# encoding: UTF-8
require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

class ContinueHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-continue", __dir__)

  def setup
    @home = Dir.mktmpdir("plastic-continue")
    plastic = File.join(@home, ".plastic")
    FileUtils.mkdir_p(File.join(plastic, "store", "1--done"))
    File.write(File.join(plastic, "store", "1--done", "1--done.md"), <<~MD)
      ---
      id: "1"
      intent: "A completed thing"
      created: 2026-05-01
      author: human
      ---
      ## Intent
      done
      ## Outcome
      done
    MD
    File.write(File.join(plastic, "INDEX.md"), <<~IDX)
      # Index
      ## Active
      ## Future
      ## Completed
      - [1 — A completed thing](store/1--done/1--done.md) — 2026-05-01
    IDX
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && File.exist?(@home)
  end

  def run_hook
    index = File.join(@home, ".plastic", "INDEX.md")
    store = File.join(@home, ".plastic")
    out, _err, status = Open3.capture3(
      { "HOME" => @home }, "ruby", SCRIPT, index, store, "global"
    )
    [out, status]
  end

  def test_emits_valid_json
    out, status = run_hook
    assert status.success?, "hook should exit 0"
    refute_empty out, "hook should print JSON"
    assert JSON.parse(out), "output must be valid JSON"
  end

  def test_additional_context_contains_dashboard_and_routing
    out, _ = run_hook
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    refute_nil ctx
    assert_includes ctx, "PLASTIC ·", "must contain the dashboard header"
    assert_includes ctx, "WHERE WE", "must contain a dashboard section heading"
    assert_includes ctx, "plastic-intent-continuing", "must contain the skill routing line"
  end

  def test_box_drawing_survives_json_roundtrip
    out, _ = run_hook
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "╔", "box-drawing characters must survive JSON encoding"
  end

  # Task 6 (intent 125): hook-continue now also emits a top-level systemMessage
  # floor, independent of additionalContext, mirroring the boot banner's two
  # channel pattern (see BootBanner). The fixture has zero active/future intents.
  def test_system_message_present_single_line_reflects_counts
    out, _ = run_hook
    data = JSON.parse(out)
    assert data.key?("systemMessage"), "top-level systemMessage key missing"
    msg = data["systemMessage"]
    refute_includes msg, "\n", "systemMessage must be a single line"
    assert_includes msg, "0 active", "expected fixture counts (0 active) reflected"
    assert_includes msg, "0 next", "expected fixture counts (0 next) reflected"
  end
end
