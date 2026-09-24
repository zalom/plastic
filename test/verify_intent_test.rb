# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "open3"
require_relative "../scripts/lib/verify_intent"

# verify-intent (intent 213): drives the LIB in process for every check that needs an
# injected seam (a fake doctor lambda, a fake suite runner), and the real SCRIPT as a
# subprocess (test/end_intent_test.rb:44-49's IO.popen pattern) only for the pure
# CLI-parsing usage failures that touch neither doctor nor a repo. Hermetic: every fixture
# lives under Dir.mktmpdir, no eval, no network, no ambient session id, no real ~/.plastic
# read. Plastic runs no version control command (intent 390): the em-dash guard and the
# diffstat print the git command instead of running it, so neither test needs a real repo
# or a fake git runner; `--diff-file`/`diff_text:` is how a caller still gates the em-dash
# guard on real content.
class VerifyIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/verify-intent", __dir__)

  # Built from its codepoint, matching VerifyIntent::EM_DASH's own construction, so this
  # fixture file's source stays free of the literal byte too.
  EM_DASH = "—"

  def setup
    @home = Dir.mktmpdir("verify-intent-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
    @tmp_bridge = Dir.mktmpdir("verify-intent-bridge")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp_bridge)
  end

  # --- fixtures --------------------------------------------------------------------

  def build_intent_dir(id: "213", slug: "demo", store: @store)
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    dir
  end

  # A registered project whose code worktree already exists on disk, so
  # ScaffoldIntent.resolve_repo_dir names a real repo (no git call either way).
  def build_project_with_repo(slug: "demo", id: "213")
    repo = File.join(@home, "apps", slug)
    FileUtils.mkdir_p(repo)
    File.write(File.join(@plastic_home, "projects.yml"), { "projects" => { slug => { "path" => repo } } }.to_yaml)
    build_intent_dir(id: id, slug: slug)
    code_wt = File.join(repo, ".claude", "worktrees", "#{id}--#{slug}")
    FileUtils.mkdir_p(code_wt)
    repo
  end

  def doctor_hash(status, checks: [])
    { version: "1.0.0", timestamp: "2026-01-01T00:00:00Z", status: status, agent: "claude",
      checks: checks, summary: { pass: 0, warn: 0, fail: 0, total: checks.size } }
  end

  def passing_doctor
    ->(home:, scope:, id:) { doctor_hash("pass") }
  end

  def run_script(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  # --- 1. the em-dash guard fixture (its own named criterion; pure text scan) -------

  def test_emdash_fixture_finds_exactly_one_violation_on_the_added_line
    diff = <<~DIFF
      diff --git a/scripts/thing.rb b/scripts/thing.rb
      index abc123..def456 100644
      --- a/scripts/thing.rb
      +++ b/scripts/thing.rb
      @@ -1,4 +1,5 @@
       context line with #{EM_DASH} inside it
      -removed line with #{EM_DASH} inside it
      +clean added line
      +added line with #{EM_DASH} violation
    DIFF

    violations = VerifyIntent.em_dash_violations(diff)

    assert_equal 1, violations.size
    assert_equal "scripts/thing.rb", violations.first[:file]
    assert_equal "added line with #{EM_DASH} violation", violations.first[:text]
  end

  # --- 2. zero violations when the only em dash is on a removed line ----------------

  def test_zero_violations_when_only_the_removed_line_carries_the_dash
    diff = <<~DIFF
      diff --git a/scripts/thing.rb b/scripts/thing.rb
      --- a/scripts/thing.rb
      +++ b/scripts/thing.rb
      @@ -1,1 +1,1 @@
      -old line with #{EM_DASH} inside it
      +new line, clean
    DIFF

    build_project_with_repo
    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, diff_text: diff,
                                doctor: passing_doctor)

    assert_equal 0, verdict[:exit_code]
    assert_equal "pass", verdict[:checks][:emdash][:status]
    assert_empty verdict[:checks][:emdash][:violations]
  end

  # --- 3. exit code 3, location names file + line derived from the hunk header ------

  def test_violation_yields_exit_3_with_file_and_line_named
    diff = <<~DIFF
      diff --git a/scripts/thing.rb b/scripts/thing.rb
      --- a/scripts/thing.rb
      +++ b/scripts/thing.rb
      @@ -1,2 +1,3 @@
       context line
      +clean added line
      +bad line #{EM_DASH} here
    DIFF

    build_project_with_repo
    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, diff_text: diff,
                                doctor: passing_doctor)

    assert_equal 3, verdict[:exit_code]
    violation = verdict[:checks][:emdash][:violations].first
    assert_equal "scripts/thing.rb", violation[:file]
    assert_kind_of Integer, violation[:line]
    assert_includes verdict[:lines].join("\n"), "scripts/thing.rb:#{violation[:line]}:"
  end

  # --- 4. exemptions: store/, .plastic/, INDEX.md, test/fixtures/ -------------------

  def diff_with_added_dash_under(path)
    <<~DIFF
      diff --git a/#{path} b/#{path}
      --- a/#{path}
      +++ b/#{path}
      @@ -1,1 +1,1 @@
      -old line
      +new line #{EM_DASH} here
    DIFF
  end

  def test_exempt_under_store_dir
    assert_empty VerifyIntent.em_dash_violations(diff_with_added_dash_under("store/x.md"))
  end

  def test_exempt_under_dot_plastic_segment
    assert_empty VerifyIntent.em_dash_violations(diff_with_added_dash_under(".plastic/store/x.md"))
  end

  def test_exempt_on_index_md
    assert_empty VerifyIntent.em_dash_violations(diff_with_added_dash_under("INDEX.md"))
  end

  def test_exempt_under_test_fixtures_dir
    assert_empty VerifyIntent.em_dash_violations(diff_with_added_dash_under("test/fixtures/x.md"))
  end

  # --- 5. doctor fail / warn / pass ---------------------------------------------------

  def test_doctor_fail_yields_exit_2
    checks = [{ category: "intent_end", name: "structure", status: "fail", message: "broken", details: [] }]
    doctor = ->(home:, scope:, id:) { doctor_hash("fail", checks: checks) }
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: doctor)

    assert_equal 2, verdict[:exit_code]
    assert_equal "fail", verdict[:checks][:doctor][:status]
  end

  def test_doctor_warn_yields_exit_0_and_prints_the_warning
    checks = [{ category: "intent_end", name: "links", status: "warn", message: "stale link", details: [] }]
    doctor = ->(home:, scope:, id:) { doctor_hash("warn", checks: checks) }
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: doctor)

    assert_equal 0, verdict[:exit_code]
    assert_equal "warn", verdict[:checks][:doctor][:status]
    assert_includes verdict[:lines].join("\n"), "stale link"
  end

  def test_doctor_pass_yields_exit_0
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: passing_doctor)

    assert_equal 0, verdict[:exit_code]
    assert_equal "pass", verdict[:checks][:doctor][:status]
  end

  # --- 6. a raising doctor is fail-open ------------------------------------------------

  def test_doctor_crash_is_fail_open
    doctor = ->(home:, scope:, id:) { raise "boom" }
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: doctor)

    assert_equal 0, verdict[:exit_code]
    assert_equal "crashed", verdict[:checks][:doctor][:status]
    assert_includes verdict[:lines].join("\n"), "doctor crashed"
  end

  # --- 7. --suite exit codes -----------------------------------------------------------

  def test_suite_nonzero_yields_exit_4
    build_project_with_repo
    suite_runner = ->(_command, _dir) { ["boom output", 1] }

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home,
                                doctor: passing_doctor, suite: "bundle exec rake", suite_runner: suite_runner)

    assert_equal 4, verdict[:exit_code]
    assert_equal "fail", verdict[:checks][:suite][:status]
  end

  def test_suite_zero_yields_exit_0
    build_project_with_repo
    suite_runner = ->(_command, _dir) { ["all green", 0] }

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home,
                                doctor: passing_doctor, suite: "bundle exec rake", suite_runner: suite_runner)

    assert_equal 0, verdict[:exit_code]
    assert_equal "pass", verdict[:checks][:suite][:status]
  end

  # --- 8. no --suite means the suite runner seam is never called ----------------------

  def test_no_suite_flag_never_calls_the_suite_runner
    build_project_with_repo
    called = false
    suite_runner = ->(_command, _dir) { called = true; ["", 0] }

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home,
                                doctor: passing_doctor, suite_runner: suite_runner)

    refute called
    assert_equal "skipped", verdict[:checks][:suite][:status]
  end

  # --- 9. precedence: doctor(2) < emdash(3) < suite(4) picks the lowest ---------------

  def test_precedence_picks_the_lowest_failing_code_and_reports_all_three
    checks = [{ category: "intent_end", name: "structure", status: "fail", message: "broken", details: [] }]
    doctor = ->(home:, scope:, id:) { doctor_hash("fail", checks: checks) }
    diff = <<~DIFF
      diff --git a/scripts/thing.rb b/scripts/thing.rb
      --- a/scripts/thing.rb
      +++ b/scripts/thing.rb
      @@ -1,1 +1,2 @@
       context line
      +bad line #{EM_DASH} here
    DIFF
    suite_runner = ->(_command, _dir) { ["suite boom", 1] }
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: doctor, diff_text: diff,
                                suite: "rake", suite_runner: suite_runner)

    assert_equal 2, verdict[:exit_code]
    joined = verdict[:lines].join("\n")
    assert_includes joined, "doctor: FAIL"
    assert_includes joined, "scripts/thing.rb:"
    assert_includes joined, "suite: exit 1"
  end

  # --- 10. usage failures exit 1 (pure CLI parsing / path resolution, no injection) ---

  def test_usage_missing_store_exits_1
    _out, status = run_script("--id", "213")
    assert_equal 1, status
  end

  def test_usage_missing_id_exits_1
    _out, status = run_script("--store", @store)
    assert_equal 1, status
  end

  def test_usage_id_matches_no_directory_exits_1
    _out, status = run_script("--store", @store, "--id", "999999")
    assert_equal 1, status
  end

  def test_usage_id_matches_two_directories_exits_1
    FileUtils.mkdir_p(File.join(@store, "213--first"))
    FileUtils.mkdir_p(File.join(@store, "213--second"))

    _out, status = run_script("--store", @store, "--id", "213")
    assert_equal 1, status
  end

  def test_usage_unknown_flag_exits_1
    _out, status = run_script("--store", @store, "--id", "213", "--nope", "x")
    assert_equal 1, status
  end

  # --- 11. --base overrides the auto-detected base for the printed instructions ------

  def test_base_flag_overrides_the_printed_instructions
    build_project_with_repo

    verdict = VerifyIntent.run(store: @store, id: "213", base: "custom-base", home: @home,
                                doctor: passing_doctor)

    joined = verdict[:lines].join("\n")
    assert_includes joined, "custom-base...HEAD"
  end

  # --- 12. no repo resolvable: emdash + diffstat skipped, doctor still runs -----------

  def test_no_repo_resolvable_skips_emdash_and_diffstat_but_not_doctor
    checks = [{ category: "intent_end", name: "structure", status: "fail", message: "broken", details: [] }]
    doctor = ->(home:, scope:, id:) { doctor_hash("fail", checks: checks) }
    build_intent_dir # no projects.yml, no repo

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: doctor)

    assert_equal "skipped", verdict[:checks][:emdash][:status]
    assert_equal "skipped", verdict[:checks][:diffstat][:status]
    assert_equal "fail", verdict[:checks][:doctor][:status]
    assert_equal 2, verdict[:exit_code]
  end

  # --- 13 (F17, intent 331f): Report savepoint lines surface in the verdict -----

  def test_verify_intent_lists_report_lines
    dir = build_intent_dir
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-09-05T12:00:00Z  What  213--demo.md
      2026-09-05T12:05:00Z  Report  state
      2026-09-05T12:10:00Z  Report  delivered
    SP

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: passing_doctor)

    assert_equal "pass", verdict[:checks][:report][:status]
    assert_equal 2, verdict[:checks][:report][:lines].length
    joined = verdict[:lines].join("\n")
    assert_includes joined, "Report  state"
    assert_includes joined, "Report  delivered"
  end

  def test_verify_intent_report_check_passes_with_no_report_lines
    build_intent_dir

    verdict = VerifyIntent.run(store: @store, id: "213", home: @home, doctor: passing_doctor)

    assert_equal "pass", verdict[:checks][:report][:status]
    assert_equal [], verdict[:checks][:report][:lines]
  end
end
