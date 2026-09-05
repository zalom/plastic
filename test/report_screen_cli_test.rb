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

  # --- fix (2026-09-01): the CLI's git tag reader ------------------------------
  # The installed copy lives in ~/.plastic/scripts, whose parent has a .git with
  # no tags, so the old reader (git describe next to the script) always answered
  # "not recorded"; in-repo it answered with the tag nearest HEAD, the wrong
  # version for every older intent. The reader must resolve the project's repo
  # and pick the lowest tag that CONTAINS the intent's merge commit.

  def make_tagged_repo
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(repo)
    env = { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@x", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@x" }
    git = ->(*a) { out, err, st = Open3.capture3(env, "git", "-C", repo, *a); raise "git #{a.join(' ')}: #{err}" unless st.success?; out.strip }
    git.call("init", "-q", "-b", "alpha")
    git.call("config", "commit.gpgsign", "false")
    File.write(File.join(repo, "a.txt"), "a\n")
    git.call("add", "."); git.call("commit", "-q", "-m", "first")
    first_sha = git.call("rev-parse", "--short", "HEAD")
    git.call("tag", "v1.0.0-alpha.1")
    File.write(File.join(repo, "b.txt"), "b\n")
    git.call("add", "."); git.call("commit", "-q", "-m", "second")
    git.call("tag", "v1.0.0-alpha.2")
    [repo, first_sha]
  end

  def delivered_intent(root, outcome_body)
    dir = make_intent(root, id: "12")
    File.write(File.join(dir, "spec.md"), "# Spec\n\n## Decisions\n- D1 x\n")
    File.write(File.join(dir, "savepoint.md"), "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:00Z  Done  delivered\n")
    File.write(File.join(dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n## Delivered\n#{outcome_body}\n")
    dir
  end

  def version_segment(out)
    out.lines[1].to_s.split(" · ").last.to_s.strip
  end

  def test_delivered_cli_picks_the_tag_containing_the_merge_not_the_tag_nearest_head
    repo, first_sha = make_tagged_repo
    dir = delivered_intent(File.join(@home, "store_root"), "- Merged into alpha at #{first_sha}.")
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir, "--repo", repo)
    assert_equal 0, status.exitstatus, err
    assert_equal "v1.0.0-alpha.1", version_segment(out), out.lines[1]
    ship = out.lines.find { |l| l.start_with?("| ship") }
    assert_includes ship.to_s, "v1.0.0-alpha.1"
  end

  def test_delivered_cli_record_version_beats_git
    repo, first_sha = make_tagged_repo
    dir = delivered_intent(File.join(@home, "store_root"), "- Shipped as `v9.9.9`: merged into alpha as `#{first_sha}`.")
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir, "--repo", repo)
    assert_equal 0, status.exitstatus, err
    assert_equal "v9.9.9", version_segment(out), out.lines[1]
  end

  def test_delivered_cli_never_guesses_from_head_without_a_merge_sha
    repo, _first_sha = make_tagged_repo
    dir = delivered_intent(File.join(@home, "store_root"), "- nothing shipped yet")
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir, "--repo", repo)
    assert_equal 0, status.exitstatus, err
    assert_equal "not recorded", version_segment(out), out.lines[1]
  end

  def test_delivered_cli_resolves_the_repo_from_projects_yml_next_to_the_store
    repo, first_sha = make_tagged_repo
    home = File.join(@home, "plastic_home")
    root = File.join(home, "projects", "demo")
    dir = delivered_intent(root, "- Merged into alpha at #{first_sha}.")
    File.write(File.join(home, "projects.yml"), "---\nprojects:\n  demo:\n    path: \"#{repo}\"\n")
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir)
    assert_equal 0, status.exitstatus, err
    assert_equal "v1.0.0-alpha.1", version_segment(out), out.lines[1]
  end

  # Intent 330 (D11): the header no longer collapses a known merge sha into
  # "not recorded" just because no tag was found for it - the last segment
  # names WHICH kind of identity it is, "merge <sha>" here.
  def test_delivered_cli_falls_back_to_the_merge_sha_when_no_repo_can_be_found
    dir = delivered_intent(File.join(@home, "store_root"), "- Merged into alpha at 0123abc.")
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir)
    assert_equal 0, status.exitstatus, err
    assert_equal "merge 0123abc", version_segment(out), out.lines[1]
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
      FileUtils.cp(File.join(REPO, "scripts", "lib", "session_ledger.rb"), File.join(tmp_root, "scripts", "lib", "session_ledger.rb"))
      FileUtils.cp(File.join(REPO, "scripts", "lib", "store_provisioning.rb"), File.join(tmp_root, "scripts", "lib", "store_provisioning.rb"))
      FileUtils.cp(File.join(REPO, "templates", "report-state.md"), File.join(tmp_root, "templates", "report-state.md"))

      root = File.join(tmp_root, "store_root")
      dir = make_intent(root)
      out, err, status = Open3.capture3("ruby", File.join(tmp_root, "scripts", "report-screen"), "state", dir)
      assert_equal 0, status.exitstatus, "#{layout}: #{err}"
      refute_empty out, "#{layout}: template did not resolve"
    end
  end

  # --- intent 331c: the roadmap verb (R14/R18) ---------------------------------

  def write_roadmap_fixture(root, slug: "demo")
    roadmaps = File.join(root, "roadmaps")
    FileUtils.mkdir_p(roadmaps)
    path = File.join(roadmaps, "#{slug}.md")
    File.write(path, <<~MD)
      # Roadmap: Demo
      ## Goal
      test goal.
      ## Batches
      ### Batch 1
      - [ ] 1 Alpha — queued
      ## Log
    MD
    File.write(File.join(root, "INDEX.md"), <<~IDX)
      # Index

      ## Active

      ## Future
      - [1 — Alpha](store/1--alpha/1--alpha.md) — 2026-07-10 note.

      ## Completed

      ## Abandoned
    IDX
    path
  end

  # R14: a missing file, a missing sub-verb, or an unknown sub-verb all exit 2 with an
  # empty stdout, never a silent success.
  def test_roadmap_verb_exits_2_on_bad_subverb
    root = File.join(@home, "store_root")
    path = write_roadmap_fixture(root)
    out, err, status = Open3.capture3("ruby", CLI, "roadmap", path, "bogus")
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_equal 1, err.lines.length
    assert_match(/sub-verb/, err, "the roadmap verb must validate its own sub-verb, not fall through a generic unknown-verb message")
  end

  def test_roadmap_verb_exits_2_on_missing_file
    out, err, status = Open3.capture3("ruby", CLI, "roadmap", File.join(@home, "nope.md"), "plan")
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/does not exist/, err)
  end

  def test_roadmap_verb_exits_2_on_missing_subverb
    root = File.join(@home, "store_root")
    path = write_roadmap_fixture(root)
    out, err, status = Open3.capture3("ruby", CLI, "roadmap", path)
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/plan\|state\|delivered/, err)
  end

  # R18: --store-root overrides the derived tier root, resolving entries against the
  # explicitly named store rather than the roadmap file's own parent directory.
  def test_roadmap_verb_honors_store_root_flag
    root = File.join(@home, "store_root")
    path = write_roadmap_fixture(root)
    other_root = File.join(@home, "other_root")
    FileUtils.mkdir_p(other_root)
    File.write(File.join(other_root, "INDEX.md"), <<~IDX)
      # Index

      ## Active

      ## Future

      ## Completed
      - [1 — Alpha](store/1--alpha/1--alpha.md) — 2026-07-10 delivered.

      ## Abandoned
    IDX

    out, err, status = Open3.capture3("ruby", CLI, "roadmap", path, "plan", "--store-root", other_root)
    assert_equal 0, status.exitstatus, err
    row = out.lines.find { |l| l.include?("| 1 |") }
    assert_includes row, "delivered",
      "--store-root must be consulted for INDEX reconciliation, not the roadmap's own derived tier root"
  end
end
