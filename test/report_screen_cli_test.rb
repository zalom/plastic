require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/report_screen"

# Intent 317: scripts/report-screen, the CLI over the three verbs. Exit codes,
# flag parsing, the --ansi passthrough that must never block on 316a (D2), and
# template resolution in both the in-repo and installed layouts (row 80).
class ReportScreenCliTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "report-screen")

  def setup
    @home = Dir.mktmpdir("report-screen-cli")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def make_intent(root, id: "12")
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--slug.md"), "---\nid: \"#{id}\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n## In Progress\n- [ ] Step 1 - a\n")
    File.write(File.join(dir, "savepoint.md"), "2026-08-30T12:00:00Z  What  #{id}--slug.md\n")
    File.write(File.join(root, "INDEX.md"), "# Index\n\n## Active\n- [#{id} - Demo](store/#{id}--slug/#{id}--slug.md) - tags\n\n## Future\n## Completed\n## Abandoned\n")
    dir
  end

  # --- row 73: unknown verb ----------------------------------------------------

  def test_unknown_verb_exits_two
    out, err, status = Open3.capture3("ruby", CLI, "bogus", @home)
    assert_equal 2, status.exitstatus
    assert_equal 1, err.lines.length
    assert_empty out
  end

  # --- row 74: state on a non-intent path --------------------------------------

  def test_state_on_non_intent_dir_exits_two_with_empty_stdout
    out, err, status = Open3.capture3("ruby", CLI, "state", @home)
    assert_equal 2, status.exitstatus
    assert_empty out
  end

  # --- row 75: state --all on a nonexistent store ------------------------------

  def test_state_all_on_nonexistent_store_exits_two
    out, err, status = Open3.capture3("ruby", CLI, "state", "--all", File.join(@home, "nope"))
    assert_equal 2, status.exitstatus
  end

  # --- row 76: --changed with no value -----------------------------------------

  def test_changed_with_no_value_exits_two
    root = File.join(@home, "store_root")
    dir = make_intent(root)
    out, err, status = Open3.capture3("ruby", CLI, "state", dir, "--changed")
    assert_equal 2, status.exitstatus
  end

  # --- row 77: --ansi with no renderer present falls back to plain ------------

  def test_ansi_falls_back_to_plain_when_renderer_absent
    root = File.join(@home, "store_root")
    dir = make_intent(root)
    out, err, status = Open3.capture3("ruby", CLI, "state", dir, "--ansi")
    assert_equal 0, status.exitstatus, err
    refute_empty out
    refute_match(/\e\[/, out, "no raw ANSI escapes should leak from a fallback")
  end

  # --- 317a S11 (B3/B4): --ansi delegates to ScreenPaint; the TTY guard keeps
  # pipes plain and PLASTIC_FORCE_COLOR=1 is the test seam that stands in for
  # a real terminal. maybe_paint and --renderer-path retired with the old
  # render-not-paint gap. ------------------------------------------------------

  def test_force_color_seam_paints_all_four_verbs
    root = File.join(@home, "store_root")
    dir = make_intent(root)
    env = { "PLASTIC_FORCE_COLOR" => "1" }
    [["state", dir], ["delivered", dir], ["delay", dir]].each do |verb, target|
      out, err, status = Open3.capture3(env, "ruby", CLI, verb, target, "--ansi")
      assert_equal 0, status.exitstatus, err
      assert_match(/\e\[/, out, "#{verb} --ansi under the force seam must paint")
      refute_match(/^\s*\|/, out.gsub(/\e\[[0-9;]*m/, ""), "#{verb} painted output must re-lay tables")
    end
    out, err, status = Open3.capture3(env, "ruby", CLI, "state", "--all", root, "--ansi")
    assert_equal 0, status.exitstatus, err
    assert_match(/\e\[/, out, "roster --ansi under the force seam must paint")
  end

  def test_renderer_path_flag_is_retired
    root = File.join(@home, "store_root")
    dir = make_intent(root)
    _out, err, status = Open3.capture3("ruby", CLI, "state", dir, "--renderer-path", "/tmp/x.rb")
    assert_equal 2, status.exitstatus
    assert_match(/unknown flag/, err)
  end

  # --- row 79: NO_COLOR forces plain even with --ansi ---------------------------

  def test_no_color_forces_plain
    root = File.join(@home, "store_root")
    dir = make_intent(root)
    out, err, status = Open3.capture3({ "NO_COLOR" => "1" }, "ruby", CLI, "state", dir, "--ansi")
    assert_equal 0, status.exitstatus, err
    refute_match(/\e\[/, out)
  end

  # --- fix 1 (post-execution review): the CLI must inject a REAL tag reader,
  # not the module's no-op default, so `delivered`'s version reaches the title
  # line and the ship row from production, not just from an injected test double.

  def test_delivered_cli_injects_a_real_git_tag_reader
    root = File.join(@home, "store_root")
    dir = make_intent(root, id: "12")
    File.write(File.join(dir, "spec.md"), "# Spec\n\n## Decisions\n- D1 x\n")
    File.write(File.join(dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n## Summary\nx\n")
    File.write(File.join(dir, "savepoint.md"), "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:00Z  Done  delivered\n")

    expected = `git -C #{REPO} describe --tags --abbrev=0 2>/dev/null`.strip
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir)
    assert_equal 0, status.exitstatus, err
    version_segment = out.lines[1].to_s.split(" \u00b7 ").last.to_s.strip
    if expected.empty?
      assert_equal "not recorded", version_segment
    else
      refute_equal "not recorded", version_segment,
                   "the CLI must inject a real tag reader, not the module's no-op default: #{out.lines[1]}"
      assert_includes version_segment, expected.sub(/\Av/, "")
    end
  end

  # --- row 80: template resolution, repo-shaped and install-shaped -------------

  def test_template_resolves_relative_to_dir_in_two_layouts
    ["repo_layout", "install_layout"].each do |layout|
      tmp_root = File.join(@home, layout)
      FileUtils.mkdir_p(File.join(tmp_root, "scripts", "lib"))
      FileUtils.mkdir_p(File.join(tmp_root, "templates"))
      FileUtils.cp(CLI, File.join(tmp_root, "scripts", "report-screen"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "report_screen.rb"), File.join(tmp_root, "scripts", "lib", "report_screen.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "intent_screen.rb"), File.join(tmp_root, "scripts", "lib", "intent_screen.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "savepoint.rb"), File.join(tmp_root, "scripts", "lib", "savepoint.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "lock.rb"), File.join(tmp_root, "scripts", "lib", "lock.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "screen_paint.rb"), File.join(tmp_root, "scripts", "lib", "screen_paint.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "intent_screen_ansi.rb"), File.join(tmp_root, "scripts", "lib", "intent_screen_ansi.rb"))
      FileUtils.cp(File.join(REPO, "templates", "report-state.md"), File.join(tmp_root, "templates", "report-state.md"))

      root = File.join(tmp_root, "store_root")
      dir = make_intent(root)
      out, err, status = Open3.capture3("ruby", File.join(tmp_root, "scripts", "report-screen"), "state", dir)
      assert_equal 0, status.exitstatus, "#{layout}: #{err}"
      refute_empty out, "#{layout}: template did not resolve"
    end
  end
end
