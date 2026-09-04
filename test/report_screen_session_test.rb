# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/screen_paint"

# Intent 330, O1: the shared fence walker feeding split_by_headings AND
# table_rows. A line matching a fence opener while closed opens a fence; a
# same-or-longer same-character marker with only whitespace after it closes
# one; inside a fence every line - a "#" or a "|" included - is body, never a
# new heading or a table row.
class ReportScreenFenceTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-fence")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  # --- O1.1: a "#" inside a fence must not truncate the section's body -------

  def test_fenced_hash_line_stays_in_the_body
    text = <<~MD
      ### O6. the check

      body before the fence

      ```ruby
      # Intent 329: a ruby comment that looks like a heading
      ```

      | Row | Op |
      | --- | --- |
      | 1 | a |
      | 2 | b |
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal 1, sections.length
    _heading, body = sections.first
    assert_equal 2, ReportScreen.table_rows(body).length
  end

  # --- O1.2: a real heading after a CLOSED fence still starts a section ------

  def test_heading_after_a_closed_fence_starts_a_section
    text = <<~MD
      ### First

      ```ruby
      # not a heading
      ```

      ### Second

      body
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal %w[###\ First ###\ Second], sections.map { |h, _b| h }
  end

  # --- O1.3: a tilde fence hides a "#" line the same way ----------------------

  def test_tilde_fence_hides_a_hash_line
    text = <<~MD
      ### Only heading

      ~~~
      # not a heading
      ~~~
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal 1, sections.length
  end

  # --- O1.4: an unterminated fence swallows the rest of the file --------------

  def test_unterminated_fence_keeps_later_lines_as_body
    text = <<~MD
      ### First

      ```
      # never closes
      ### Second
      more content
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal 1, sections.length
    _heading, body = sections.first
    assert_includes body, "### Second"
    assert_includes body, "more content"
  end

  # --- O1.5: a shorter inner fence marker does not close the outer fence -----

  def test_inner_shorter_fence_does_not_close
    text = <<~MD
      ### Heading

      ````
      outer opens with four backticks
      ```
      an inner three-backtick line must not close the outer fence
      ```
      # still inside the outer fence
      ````

      ### Next
      body
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal %w[###\ Heading ###\ Next], sections.map { |h, _b| h }
  end

  # --- O1.6: the live 329 regression - O6's matrix sits after a fence --------

  def test_plastic_329_o6_proves_its_matrix
    write("actions/ACTION_1.md", <<~MD)
      # ACTION_1

      ### O6. scripts/doctor.rb - the intent_ticks_lag check

      ```ruby
      # Intent 329: sample lag check
      def lag_check
        true
      end
      ```

      | # | Failure mode | Test |
      | --- | --- | --- |
      | 1 | a | test_a |
      | 2 | b | test_b |
    MD
    proven = ReportScreen.proven_by(@dir, "O6")
    refute_equal ReportScreen::NOT_RECORDED, proven
    assert_equal "2 tests", proven
  end

  # --- O1.7: a fenced pipe table is never counted as a real matrix -----------

  def test_table_rows_ignores_a_pipe_table_inside_a_fence
    section = <<~MD
      prose before

      ```markdown
      | Term | Source |
      | --- | --- |
      | Spelling | Merriam-Webster. |
      | a | b |
      | c | d |
      | e | f |
      | g | h |
      | i | j |
      ```

      | # | Op |
      | --- | --- |
      | 1 | a |
      | 2 | b |
    MD
    assert_equal 2, ReportScreen.table_rows(section).length
  end

  # --- O1.10: a four-space-indented block is NOT a fence (stated limit) ------

  def test_indented_code_block_is_not_a_fence
    text = <<~MD
      ### Heading A

      body

          ```
      # Heading B
          ```
      more
    MD
    sections = ReportScreen.split_by_headings(text)
    assert_equal %w[###\ Heading\ A #\ Heading\ B], sections.map { |h, _b| h }
  end
end

# Intent 330, O2: the injected branch reader replaces the "alpha" literal, and
# the header names the KIND of the shipped identity (v<version>, merge <sha>,
# or not recorded) rather than a bare, ambiguous hash.
class ReportScreenShipIdentityTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-ship")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    File.write(File.join(@dir, "12--slug.md"), "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def savepoint_done
    write("savepoint.md", "2026-08-30T12:00:00Z  What  12--slug.md\n2026-08-30T12:10:00Z  Done  delivered\n")
  end

  # --- O2.1: the injected branch reader replaces the "alpha" literal ---------

  def test_ship_row_uses_the_injected_branch
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into main at 1d1f8db.\n")
    rows = ReportScreen.evidence_rows(@dir, branch_reader: ->(_d) { "main" })
    ship = rows.find { |r| r[:kind] == "ship" }
    refute_nil ship
    assert_includes ship[:what], "1d1f8db → main"
  end

  # --- O2.2: branch and version stay together on a tagged repository ---------

  def test_ship_row_keeps_branch_and_version_together
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into alpha at 2da2b3c.\n")
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_d) { "2.0.0-alpha.12" }, branch_reader: ->(_d) { "alpha" })
    ship = rows.find { |r| r[:kind] == "ship" }
    assert_equal "2da2b3c → alpha · v2.0.0-alpha.12", ship[:what]
  end

  # --- O2.3: an unknown branch never prints an empty arrow --------------------

  def test_ship_row_omits_an_unknown_branch
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into alpha at 2da2b3c.\n")
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_d) { "2.0.0-alpha.12" }, branch_reader: ->(_d) { nil })
    ship = rows.find { |r| r[:kind] == "ship" }
    refute_includes ship[:what], "→"
    assert_includes ship[:what], "2da2b3c"
  end

# --- O2.12: an unknown version is omitted, not named ------------------------
#
# Found at the lead's post-execution review, not by the matrix: the first
# implementation appended " . not recorded" unconditionally, so a repository
# with no tags still read "1d1f8db -> main . not recorded". That is half the
# defect this intent was opened to remove, on the exact record (jobext 22)
# that motivated it.

def test_ship_row_omits_an_unknown_version
  write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into main at 1d1f8db.\n")
  rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_d) { nil }, branch_reader: ->(_d) { "main" })
  ship = rows.find { |r| r[:kind] == "ship" }
  assert_equal "1d1f8db → main", ship[:what]
  refute_includes ship[:what], ReportScreen::NOT_RECORDED
end

  # --- O2.4: the header falls back to the prefixed merge sha -----------------

  def test_header_falls_back_to_the_prefixed_merge_sha
    savepoint_done
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into alpha at 1d1f8db.\n")
    out = ReportScreen.render_delivered(intent_dir: @dir, tag_reader: ->(_d) { nil })
    assert_equal "merge 1d1f8db", out.lines[1].split(" · ").last.strip
  end

  # --- O2.5: the header prefers the version when one is known -----------------

  def test_header_prefers_the_version
    savepoint_done
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into alpha at 1d1f8db.\n")
    out = ReportScreen.render_delivered(intent_dir: @dir, tag_reader: ->(_d) { "2.0.0-alpha.12" })
    assert_equal "v2.0.0-alpha.12", out.lines[1].split(" · ").last.strip
  end

  # --- O2.6: the header says "not recorded" when nothing shipped -------------

  def test_header_says_not_recorded_when_nothing_shipped
    savepoint_done
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\n- nothing shipped yet\n")
    out = ReportScreen.render_delivered(intent_dir: @dir, tag_reader: ->(_d) { nil })
    assert_equal "not recorded", out.lines[1].split(" · ").last.strip
  end

  # --- O2.7: flow_base reads project.yml, nil otherwise ------------------------

  def test_flow_base_reads_project_yml_and_answers_nil_otherwise
    home = File.join(@root, "home")
    project_dir = File.join(home, "projects", "demo")
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "project.yml"), "flow:\n  base: alpha\n")
    intent_dir = File.join(home, "projects", "demo", "store", "12--slug")
    FileUtils.mkdir_p(intent_dir)
    assert_equal "alpha", ReportScreen.flow_base(intent_dir)

    no_flow_project = File.join(home, "projects", "noflow")
    FileUtils.mkdir_p(no_flow_project)
    File.write(File.join(no_flow_project, "project.yml"), "governing_docs:\n  - AGENTS.md\n")
    assert_nil ReportScreen.flow_base(File.join(home, "projects", "noflow", "store", "1--x"))

    global_intent = File.join(home, "store", "1--x")
    FileUtils.mkdir_p(global_intent)
    assert_nil ReportScreen.flow_base(global_intent)

    malformed_project = File.join(home, "projects", "bad")
    FileUtils.mkdir_p(malformed_project)
    File.write(File.join(malformed_project, "project.yml"), "flow: [oops\n")
    assert_nil ReportScreen.flow_base(File.join(home, "projects", "bad", "store", "1--x"))
  end

  # --- O2.8/O2.9/O2.10: the real CLI branch reader ----------------------------

  CLI = File.expand_path("../scripts/report-screen", __dir__)

  def make_repo(branch:)
    repo = File.join(@root, "repo-#{branch}")
    FileUtils.mkdir_p(repo)
    env = { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@x", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@x" }
    git = lambda do |*a|
      out, err, st = Open3.capture3(env, "git", "-C", repo, *a)
      raise "git #{a.join(' ')}: #{err}" unless st.success?

      out.strip
    end
    git.call("init", "-q", "-b", branch)
    git.call("config", "commit.gpgsign", "false")
    File.write(File.join(repo, "a.txt"), "a\n")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "first")
    repo
  end

  def make_delivered_intent(root, id: "12")
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--slug.md"), "---\nid: \"#{id}\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    File.write(File.join(dir, "savepoint.md"), "2026-08-30T12:00:00Z  What  #{id}--slug.md\n2026-08-30T12:10:00Z  Done  delivered\n")
    File.write(File.join(dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into master at 1d1f8db.\n")
    File.write(File.join(root, "INDEX.md"), "# Index\n\n## Active\n\n## Completed\n- [#{id} - Demo](store/#{id}--slug/#{id}--slug.md) - tags\n")
    dir
  end

  def ship_row_line(out)
    out.lines.find { |l| l.start_with?("| ship") }
  end

  def test_cli_branch_reader_prefers_flow_base
    repo = make_repo(branch: "master")
    home = File.join(@root, "plastic_home")
    project_dir = File.join(home, "projects", "demo")
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "project.yml"), "flow:\n  base: alpha\n")
    File.write(File.join(home, "projects.yml"), "---\nprojects:\n  demo:\n    path: \"#{repo}\"\n")
    dir = make_delivered_intent(project_dir)
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir)
    assert_equal 0, status.exitstatus, err
    assert_includes ship_row_line(out).to_s, "→ alpha"
  end

  def test_cli_branch_reader_falls_back_to_main
    repo = make_repo(branch: "main")
    Open3.capture3("git", "-C", repo, "branch", "feature")
    Open3.capture3("git", "-C", repo, "checkout", "feature")
    dir = make_delivered_intent(File.join(@root, "store_root"))
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir, "--repo", repo)
    assert_equal 0, status.exitstatus, err
    assert_includes ship_row_line(out).to_s, "→ main"
  end

  def test_branch_reader_is_nil_for_a_global_store_intent
    home = File.join(@root, "global_home")
    dir = make_delivered_intent(home)
    out, err, status = Open3.capture3("ruby", CLI, "delivered", dir)
    assert_equal 0, status.exitstatus, err
    line = ship_row_line(out).to_s
    refute_includes line, "→"
  end

  # --- O2.11: the Source cell names where the branch came from ----------------

  def test_ship_row_source_names_where_the_branch_came_from
    home = File.join(@root, "home2")
    project_dir = File.join(home, "projects", "demo")
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "project.yml"), "flow:\n  base: alpha\n")
    intent_dir = File.join(project_dir, "store", "12--slug")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "12--slug.md"), "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    File.write(File.join(intent_dir, "savepoint.md"), "2026-08-30T12:00:00Z  What  x\n2026-08-30T12:10:00Z  Done  delivered\n")
    File.write(File.join(intent_dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n## Delivered\n- Merged into alpha at 2da2b3c.\n")

    rows = ReportScreen.evidence_rows(intent_dir, branch_reader: ->(_d) { "alpha" })
    ship = rows.find { |r| r[:kind] == "ship" }
    assert_includes ship[:source], "project.yml"
  end
end

# Intent 330, O3: `report-screen session <tier_root>` - the session verb.
class ReportScreenSessionVerbTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-session")
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(@home)
    @ledger_root = File.join(@home, "store", ".sessions")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write_index(store, active: [], completed: [], abandoned: [])
    lines = ["# Index", "", "## Active"]
    active.each { |id, name| lines << "- [#{id} - #{name}](store/#{id}--slug/#{id}--slug.md) - tags" }
    lines << "" << "## Future" << "" << "## Completed"
    completed.each { |id, name| lines << "- [#{id} - #{name}](store/#{id}--slug/#{id}--slug.md) - tags" }
    lines << "" << "## Abandoned"
    abandoned.each { |id, name| lines << "- [#{id} - #{name}](store/#{id}--slug/#{id}--slug.md) - tags" }
    FileUtils.mkdir_p(store)
    File.write(File.join(store, "INDEX.md"), lines.join("\n") + "\n")
  end

  def write_intent(store, id, done_ts: nil, name: "Demo")
    dir = File.join(store, "store", "#{id}--slug")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--slug.md"), "---\nid: \"#{id}\"\nintent: \"#{name}\"\n---\n\n## Intent\n#{name}\n")
    sp = "2026-08-30T09:00:00Z  What  x\n"
    sp += "#{done_ts}  Done  delivered\n" if done_ts
    File.write(File.join(dir, "savepoint.md"), sp)
    File.write(File.join(dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n## Delivered\n- shipped\n") if done_ts
    dir
  end

  def write_ledger_line(day, ts:, session:, slug:)
    dir = File.join(@ledger_root, day)
    FileUtils.mkdir_p(dir)
    File.open(File.join(dir, "savepoint.md"), "a") { |f| f.write("#{ts}  Item  [#{session}] [#{slug}] did something\n") }
  end

  # --- O3.1/O3.2: window boundaries --------------------------------------------

  def test_window_excludes_an_earlier_done
    write_index(@home, completed: [["1", "Old"]])
    write_intent(@home, "1", done_ts: "2026-09-01T10:00:00Z")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_empty dirs
  end

  def test_window_includes_a_done_inside_it
    write_index(@home, completed: [["1", "New"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_equal 1, dirs.length
  end

  # --- O3.3: oldest Done bookend first ------------------------------------------

  def test_delivered_dirs_are_oldest_first
    write_index(@home, completed: [["1", "A"], ["2", "B"], ["3", "C"]])
    write_intent(@home, "1", done_ts: "2026-09-04T09:00:00Z")
    write_intent(@home, "2", done_ts: "2026-09-04T03:00:00Z")
    write_intent(@home, "3", done_ts: "2026-09-04T06:00:00Z")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_equal %w[2--slug 3--slug 1--slug], dirs.map { |d| File.basename(d) }
  end

  # --- O3.4/O3.5/O3.6/O3.7: which stores get scanned ---------------------------

  def test_every_store_the_session_touched_is_scanned
    project_home = File.join(@home, "projects", "demo")
    write_index(@home, completed: [["1", "Global"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_index(project_home, completed: [["2", "Proj"]])
    write_intent(project_home, "2", done_ts: "2026-09-04T06:00:00Z")
    write_ledger_line("20260904", ts: "2026-09-04T00:30:00Z", session: "abc12345", slug: "global")
    write_ledger_line("20260904", ts: "2026-09-04T00:31:00Z", session: "abc12345", slug: "demo")

    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: "abc12345", since: nil,
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    ids = dirs.map { |d| File.basename(d) }
    assert_includes ids, "1--slug"
    assert_includes ids, "2--slug"
  end

  def test_another_sessions_store_is_not_scanned
    other_home = File.join(@home, "projects", "other")
    write_index(other_home, completed: [["9", "Other"]])
    write_intent(other_home, "9", done_ts: "2026-09-04T05:00:00Z")
    write_index(@home, completed: [])
    write_ledger_line("20260904", ts: "2026-09-04T00:30:00Z", session: "zzzzzzzz", slug: "other")

    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: "abc12345", since: nil,
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    refute_includes dirs.map { |d| File.basename(d) }, "9--slug"
  end

  def test_the_named_tier_is_always_scanned
    project_home = File.join(@home, "projects", "demo")
    write_index(project_home, completed: [["2", "Proj"]])
    write_intent(project_home, "2", done_ts: "2026-09-04T05:00:00Z")
    write_ledger_line("20260904", ts: "2026-09-04T00:30:00Z", session: "abc12345", slug: "global")

    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: project_home, session: "abc12345", since: nil,
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_includes dirs.map { |d| File.basename(d) }, "2--slug"
  end

  def test_a_stale_slug_is_skipped_silently
    write_index(@home, completed: [["1", "Global"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_ledger_line("20260904", ts: "2026-09-04T00:30:00Z", session: "abc12345", slug: "ghost-project")

    dirs = nil
    assert_silent do
      dirs, = ReportScreen.session_delivered_dirs(
        ledger_root: @ledger_root, tier_root: @home, session: "abc12345", since: nil,
        now: Time.parse("2026-09-04T12:00:00Z"),
      )
    end
    assert_includes dirs.map { |d| File.basename(d) }, "1--slug"
  end

  # --- O3.8: --since overrides the ledger window -------------------------------

  def test_since_overrides_the_ledger_window
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_ledger_line("20260904", ts: "2026-09-04T08:00:00Z", session: "abc12345", slug: "global")

    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: "abc12345", since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_equal 1, dirs.length
  end

  # --- O3.9: a full harness session id matches its ledger short form ----------

  def test_session_id_is_matched_by_its_short_form
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_ledger_line("20260904", ts: "2026-09-04T00:30:00Z", session: "abc12345", slug: "global")

    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: "ABC12345-full-harness-uuid-suffix", since: nil,
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_equal 1, dirs.length
  end

  # --- O3.10: no session names uses the whole day ------------------------------

  def test_no_session_uses_the_whole_day
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: nil,
      now: Time.new(2026, 9, 4, 12, 0, 0, "+00:00"),
    )
    assert_equal 1, dirs.length
  end

  # --- O3.11/O3.12: day fallback ------------------------------------------------

  def test_missing_day_falls_back_to_the_newest_past_day
    FileUtils.mkdir_p(File.join(@ledger_root, "20260902"))
    day = ReportScreen.fallback_day(@ledger_root, "20260904")
    assert_equal "20260902", day
  end

  def test_future_day_directories_are_ignored
    FileUtils.mkdir_p(File.join(@ledger_root, "20260902"))
    FileUtils.mkdir_p(File.join(@ledger_root, "20991231"))
    day = ReportScreen.fallback_day(@ledger_root, "20260904")
    assert_equal "20260902", day
  end

  # --- O3.13: no ledger at all answers an empty window, not an error ----------

  def test_no_ledger_answers_an_empty_window_not_an_error
    write_index(@home, completed: [])
    dirs = nil
    assert_silent do
      dirs, = ReportScreen.session_delivered_dirs(
        ledger_root: @ledger_root, tier_root: @home, session: nil, since: nil,
        now: Time.new(2026, 9, 4, 12, 0, 0, "+00:00"),
      )
    end
    assert_equal [], dirs
  end

  # --- O3.14/O3.15/O3.16: render_session shape ---------------------------------

  def test_render_session_ends_with_the_roster
    write_index(@home, completed: [])
    out = ReportScreen.render_session(dirs: [], skipped: 0, store_root: @home)
    assert_match(/No intents in delivery\.\s*\z/, out)
  end

  def test_render_session_says_so_when_nothing_was_delivered
    write_index(@home, completed: [])
    out = ReportScreen.render_session(dirs: [], skipped: 0, store_root: @home)
    lines = out.lines.map(&:chomp)
    assert_equal "No intents delivered in this session.", lines.first
  end

  def test_render_session_separates_screens_with_a_blank_line
    write_index(@home, completed: [["1", "A"], ["2", "B"]])
    dir1 = write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    dir2 = write_intent(@home, "2", done_ts: "2026-09-04T06:00:00Z")
    out = ReportScreen.render_session(dirs: [dir1, dir2], skipped: 0, store_root: @home)
    assert_match(/\n\n## ✔ 2 · /, out)
  end

  # --- O3.17/O3.18/O3.19: the CLI verb ------------------------------------------

  CLI = File.expand_path("../scripts/report-screen", __dir__)

  def test_cli_session_verb_prints_screens_and_roster
    write_index(@home, active: [["9", "Live"]], completed: [["1", "A"]])
    FileUtils.mkdir_p(File.join(@home, "store", "9--slug"))
    File.write(File.join(@home, "store", "9--slug", "9--slug.md"), "---\nid: \"9\"\nintent: \"Live\"\n---\n\n## Intent\nLive\n")
    File.write(File.join(@home, "store", "9--slug", "savepoint.md"), "2026-09-04T09:00:00Z  What  9--slug.md\n")
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    out, err, status = Open3.capture3("ruby", CLI, "session", @home, "--since", "2026-09-04T00:00:00Z", "--ledger-root", @ledger_root)
    assert_equal 0, status.exitstatus, err
    assert_includes out, "✔ 1 · "
    assert_includes out, "In delivery"
  end

  def test_cli_session_rejects_a_non_store_root
    out, err, status = Open3.capture3("ruby", CLI, "session", File.join(@home, "nope"))
    assert_equal 2, status.exitstatus
    assert_empty out
    refute_empty err
  end

  def test_cli_session_rejects_an_unknown_flag
    write_index(@home, completed: [])
    out, _err, status = Open3.capture3("ruby", CLI, "session", @home, "--bogus")
    assert_equal 2, status.exitstatus
    assert_empty out
  end

  def test_cli_session_accepts_ansi
    write_index(@home, completed: [])
    out, err, status = Open3.capture3("ruby", CLI, "session", @home, "--ansi", "--since", "2026-09-04T00:00:00Z")
    assert_equal 0, status.exitstatus, err
    refute_match(/\e\[/, out)
  end

  # --- O3.20: session_delivered_dirs never reads the ambient clock ------------

  def test_session_delivered_dirs_takes_its_clock_and_ledger_as_arguments
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    dirs_a, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T09:00:00Z"),
    )
    dirs_b, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T18:00:00Z"),
    )
    assert_equal dirs_a.map { |d| File.basename(d) }, dirs_b.map { |d| File.basename(d) }
  end

  # --- O3.21: no session id names widen the window VISIBLY --------------------

  def test_no_session_id_does_not_silently_widen_the_window
    write_index(@home, completed: [])
    out_no_session, err, status = Open3.capture3({ "CLAUDE_CODE_SESSION_ID" => nil }, "ruby", CLI, "session", @home)
    assert_equal 0, status.exitstatus, err
    assert_match(/\AWindow: the whole of/, out_no_session)

    out_with_session, err2, status2 = Open3.capture3({ "CLAUDE_CODE_SESSION_ID" => "abc12345" }, "ruby", CLI, "session", @home)
    assert_equal 0, status2.exitstatus, err2
    refute_match(/\AWindow: the whole of/, out_with_session)
  end

  # --- O3.22: the default ledger root -------------------------------------------

  def test_ledger_root_defaults_from_a_global_tier_root
    home = File.join(@root, "g")
    assert_equal File.join(home, "store", ".sessions"), ReportScreen.default_ledger_root(home)
  end

  def test_ledger_root_defaults_from_a_project_tier_root
    home = File.join(@root, "p")
    tier_root = File.join(home, "projects", "demo")
    assert_equal File.join(home, "store", ".sessions"), ReportScreen.default_ledger_root(tier_root)
  end

  # --- O3.23/O3.24: local midnight, not UTC midnight ---------------------------

  def test_the_whole_day_window_opens_at_local_midnight_not_utc_midnight
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-03T22:30:00Z")
    now = Time.new(2026, 9, 4, 10, 0, 0, "+02:00")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: nil, now: now,
    )
    assert_equal 1, dirs.length
  end

  def test_a_session_spanning_midnight_opens_at_its_first_line_yesterday
    write_index(@home, completed: [["1", "A"]])
    write_intent(@home, "1", done_ts: "2026-09-03T22:15:00Z")
    write_ledger_line("20260903", ts: "2026-09-03T22:00:00Z", session: "abc12345", slug: "global")
    write_ledger_line("20260904", ts: "2026-09-04T00:05:00Z", session: "abc12345", slug: "global")
    now = Time.new(2026, 9, 4, 10, 0, 0, "+00:00")
    dirs, = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: "abc12345", since: nil, now: now,
    )
    assert_equal 1, dirs.length
  end

  # --- O3.25: per-screen painting - one bad screen never unpaints the rest ----

  def test_cli_session_paints_each_screen_independently
    write_index(@home, completed: [["1", "A"], ["2", "B"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_intent(@home, "2", done_ts: nil)
    env = { "PLASTIC_FORCE_COLOR" => "1" }
    out, err, status = Open3.capture3(env, "ruby", CLI, "session", @home, "--since", "2026-09-04T00:00:00Z", "--ansi")
    assert_equal 0, status.exitstatus, err
    # The skipped-footer line is plain prose ScreenPaint cannot parse as a
    # screen; it must still survive verbatim beside the painted delivered
    # screen and roster (D21: one bad block never costs the others).
    assert_match(/\e\[/, out)
    assert_includes out, "completed intent skipped"
  end

  # --- O3.26: the empty-session line is a known closer ------------------------

  def test_screen_paint_classifies_the_empty_session_line
    refute_nil ScreenPaint.paint("No intents delivered in this session.", color: true)
  end

  # --- O3.27: a completed intent with no Done bookend is counted, not hidden -

  def test_completed_intents_without_a_done_bookend_are_counted_in_a_footer
    write_index(@home, completed: [["1", "A"], ["2", "B"]])
    write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    write_intent(@home, "2", done_ts: nil)
    dirs, skipped = ReportScreen.session_delivered_dirs(
      ledger_root: @ledger_root, tier_root: @home, session: nil, since: "2026-09-04T00:00:00Z",
      now: Time.parse("2026-09-04T12:00:00Z"),
    )
    assert_equal 1, skipped
    out = ReportScreen.render_session(dirs: dirs, skipped: skipped, store_root: @home)
    assert_includes out, "1 completed intent skipped"
  end

  def test_footer_absent_when_nothing_was_skipped
    write_index(@home, completed: [["1", "A"]])
    dir = write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    out = ReportScreen.render_session(dirs: [dir], skipped: 0, store_root: @home)
    refute_includes out, "skipped"
  end

  # --- O3.28: one unrenderable directory does not sink the whole report ------

  def test_render_session_survives_a_directory_that_cannot_render
    write_index(@home, completed: [["1", "A"], ["2", "B"]])
    dir1 = write_intent(@home, "1", done_ts: "2026-09-04T05:00:00Z")
    dir2 = write_intent(@home, "2", done_ts: "2026-09-04T06:00:00Z")
    boom = ->(d) { raise "boom" if d == dir1 }
    out = ReportScreen.render_session(dirs: [dir1, dir2], skipped: 0, store_root: @home, tag_reader: boom)
    assert_includes out, "✔ 2 · "
    assert_includes out, "No intents in delivery."
  end
end
