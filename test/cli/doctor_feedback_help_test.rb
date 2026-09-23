# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "json"
require_relative "../../scripts/lib/cli"

# Family 4 (intent 372): `plastic doctor`, `plastic feedback`, and the help
# topics that absorb the retired tutorial and conventions skills.
class CliDoctorFeedbackHelpTest < Minitest::Test
  PASSING_REPORT = JSON.generate("version" => "0.0.0", "status" => "pass",
    "agent" => "claude", "checks" => []).freeze

  KNOWN_TOPICS = %w[completion-and-done knowledge-graph lifecycle-and-savepoints
    locks-and-worktrees maintenance-and-revisions roadmaps track-1-guided
    track-2-auto track-3-projects-and-roadmaps].freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
    @calls = []
  end

  # The doctor command captures the script's stdout so it can render the report
  # as a screen, so the runner seam answers both shapes: a status on its own,
  # and stdout with that status when asked to capture.
  def command(verb, *argv, status: 0, env: {}, report: nil)
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments, capture: false|
      @calls << [path, arguments]
      next status unless capture

      [report || PASSING_REPORT, status]
    end
    Plastic::CLI::Commands.const_get(const).call(argv, out: @out, err: @err, env: env,
      home: "/nowhere", runner: runner)
  end

  def help(*argv)
    require_relative "../../scripts/lib/cli/commands/help"
    Plastic::CLI::Commands::Help.call(argv, out: @out, err: @err, env: {}, home: "/nowhere")
  end

  # --- doctor ---------------------------------------------------------

  def test_doctor_runs_doctor_rb
    command("doctor")

    assert_equal [File.expand_path("../../scripts/doctor.rb", __dir__)], @calls.map(&:first)
  end

  def test_doctor_flags_reach_the_script_unchanged
    command("doctor", "--core", "--store", "plastic")

    assert_equal [["--core", "--store", "plastic"]], @calls.map(&:last)
  end

  def test_doctor_accepts_an_explicit_harness
    assert_equal 0, command("doctor", "--core", "--agent", "codex")
    assert_equal [["--core", "--agent", "codex"]], @calls.map(&:last)
  end

  def test_doctor_has_no_fix_flag
    file, const, = Plastic::CLI::TABLE.fetch("doctor")
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    klass = Plastic::CLI::Commands.const_get(const)

    refute_includes klass::FLAGS, "--fix"
    refute_includes klass::USAGE_LINE, "--fix"
  end

  # --- feedback ---------------------------------------------------------

  def test_feedback_runs_feedback_report_with_the_title_flag
    command("feedback", "Something broke")

    assert_equal [File.expand_path("../../scripts/feedback-report", __dir__)], @calls.map(&:first)
    assert_equal [["--title", "Something broke"]], @calls.map(&:last)
  end

  def test_feedback_with_no_title_exits_usage
    assert_equal 2, command("feedback")
  end

  def test_feedback_with_a_blank_title_exits_usage
    assert_equal 2, command("feedback", "  ")
  end

  def test_feedback_with_a_failing_script_exits_one
    assert_equal 1, command("feedback", "Something broke", status: 7)
  end

  def test_feedback_with_no_title_never_runs_the_script
    command("feedback")

    assert_empty @calls
  end

  # --- help topics ---------------------------------------------------------

  def test_a_known_topic_prints_the_shipped_chapter_content
    chapter_path = File.expand_path("../../docs/help/roadmaps.md", __dir__)

    status = help("roadmaps")

    assert_equal 0, status
    assert_includes @out.string, File.read(chapter_path)
  end

  def test_an_unknown_topic_exits_with_the_usage_code
    assert_equal 2, help("not-a-real-topic-or-command")
  end

  def test_bare_help_lists_every_shipped_topic
    status = help

    assert_equal 0, status
    KNOWN_TOPICS.each { |topic| assert_includes @out.string, topic }
  end

  def test_a_command_name_wins_over_a_topic_of_the_same_name
    status = help("doctor")

    assert_equal 0, status
    assert_includes @out.string, "usage"
    refute_includes @out.string, File.read(File.expand_path("../../docs/help/roadmaps.md", __dir__))
  end

  # --- the four absorbed skills are gone ---------------------------------

  def test_the_four_absorbed_skill_directories_are_gone
    %w[doctor feedback tutorial conventions].each do |name|
      refute_path_exists File.expand_path("../../skills/#{name}", __dir__)
    end
  end
end

# doctor.rb speaks JSON and nothing rendered it, so `plastic doctor` printed a
# 60-check document at a reader who wanted one line. The command renders a
# screen, keeps the document behind --json, and exits non-zero on a finding.
class CliDoctorScreenTest < Minitest::Test
  WARNING_REPORT = JSON.generate(
    "version" => "2.0.0-alpha.29",
    "status" => "warn",
    "agent" => "claude",
    "checks" => [
      {"category" => "global_store", "name" => "index_exists", "status" => "pass", "message" => "ok"},
      {"category" => "session_ledger", "name" => "orphaned_session_tmp", "status" => "warn",
       "message" => "26 stale directories", "fix_hint" => "Remove each listed directory"}
    ]
  ).freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
  end

  def doctor(*argv, report:)
    require_relative "../../scripts/lib/cli/commands/doctor"
    runner = lambda do |_path, _arguments, capture: false|
      capture ? [report, 0] : 0
    end
    Plastic::CLI::Commands::Doctor.call(argv, out: @out, err: @err, env: {},
      home: "/nowhere", runner: runner)
  end

  def passing_report
    JSON.generate("version" => "1.2.3", "status" => "pass", "agent" => "claude",
      "checks" => [{"name" => "one", "status" => "pass", "message" => "ok"}])
  end

  def test_a_passing_report_exits_zero
    assert_equal 0, doctor(report: passing_report)
  end

  def test_a_passing_report_counts_the_checks_and_names_the_version
    doctor(report: passing_report)

    assert_includes @out.string, "1 of 1 checks pass"
    assert_includes @out.string, "1.2.3"
  end

  def test_a_passing_report_prints_no_document
    doctor(report: passing_report)

    refute_includes @out.string, "{", "the document belongs behind --json"
  end

  def test_a_finding_is_listed_with_its_repair
    doctor(report: WARNING_REPORT)

    assert_includes @out.string, "session_ledger/orphaned_session_tmp"
    assert_includes @out.string, "26 stale directories"
    assert_includes @out.string, "fix: Remove each listed directory"
  end

  def test_a_passing_check_is_not_listed_as_a_finding
    doctor(report: WARNING_REPORT)

    refute_includes @out.string, "global_store/index_exists"
  end

  def test_a_report_that_is_not_pass_exits_non_zero
    assert_equal Plastic::CLI::Command::FAILED, doctor(report: WARNING_REPORT)
    assert_includes @err.string, "doctor found 1 finding"
  end

  def test_json_prints_the_document_and_no_screen
    doctor("--json", report: WARNING_REPORT)

    assert_equal "warn", JSON.parse(@out.string)["status"]
    refute_includes @out.string, "next:", "the document is the whole answer under --json"
  end

  def test_the_repair_line_carries_no_label_of_its_own
    doctor(report: WARNING_REPORT)

    repair = @out.string.lines.find { |line| line.include?("fix: ") }

    assert_match(/\A\s+fix: /, repair, "the repair hangs under its finding, unlabelled")
  end

  def test_a_report_that_is_not_json_fails_with_a_plain_reason
    assert_equal Plastic::CLI::Command::FAILED, doctor(report: "doctor.rb: boom")
    assert_includes @err.string, "did not print a report"
  end

  def test_json_is_not_passed_on_to_the_script
    seen = nil
    require_relative "../../scripts/lib/cli/commands/doctor"
    runner = lambda do |_path, arguments, capture: false|
      seen = arguments
      capture ? [WARNING_REPORT, 0] : 0
    end
    Plastic::CLI::Commands::Doctor.call(["--json", "--core"], out: @out, err: @err, env: {},
      home: "/nowhere", runner: runner)

    assert_equal ["--core"], seen
  end
end

# Two findings, one of them with no repair to name: the plural reading and the
# bare finding line are both shapes the screen has to hold.
class CliDoctorTwoFindingsTest < Minitest::Test
  REPORT = JSON.generate(
    "version" => "2.0.0",
    "status" => "fail",
    "agent" => "claude",
    "checks" => [
      {"category" => "install", "name" => "hooks_exist", "status" => "fail", "message" => "two hooks missing",
       "fix_hint" => "Run plastic install --reinstall"},
      {"category" => "install", "name" => "version_match", "status" => "warn", "message" => "files disagree"}
    ]
  ).freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
    require_relative "../../scripts/lib/cli/commands/doctor"
    runner = lambda { |_path, _arguments, capture: false| capture ? [REPORT, 0] : 0 }
    Plastic::CLI::Commands::Doctor.call([], out: @out, err: @err, env: {},
      home: "/nowhere", runner: runner)
  end

  def test_more_than_one_finding_reads_as_findings
    assert_includes @err.string, "doctor found 2 findings"
  end

  def test_a_finding_with_no_repair_prints_no_repair_line
    lines = @out.string.lines.select { |line| line.include?("fix: ") }

    assert_equal 1, lines.size, "only the finding that names a repair gets a repair line"
  end

  def test_both_findings_are_listed
    assert_includes @out.string, "install/hooks_exist"
    assert_includes @out.string, "install/version_match"
  end
end

# A flag doctor does not have is a usage error, and no child runs for it.
class CliDoctorUnknownFlagTest < Minitest::Test
  def test_an_unknown_flag_exits_usage_and_runs_nothing
    out = StringIO.new
    err = StringIO.new
    ran = false
    require_relative "../../scripts/lib/cli/commands/doctor"
    runner = lambda { |_path, _arguments, capture: false|
      ran = true
      capture ? ["{}", 0] : 0
    }

    status = Plastic::CLI::Commands::Doctor.call(["--fix"], out: out, err: err, env: {},
      home: "/nowhere", runner: runner)

    assert_equal Plastic::CLI::Command::USAGE, status
    refute ran, "a usage error never reaches the script"
  end
end
