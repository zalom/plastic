# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../scripts/lib/cli"

# Family 4 (intent 372): `plastic doctor`, `plastic feedback`, and the help
# topics that absorb the retired tutorial and conventions skills.
class CliDoctorFeedbackHelpTest < Minitest::Test
  KNOWN_TOPICS = %w[completion-and-done knowledge-graph lifecycle-and-savepoints
    locks-and-worktrees maintenance-and-revisions roadmaps track-1-guided
    track-2-auto track-3-projects-and-roadmaps].freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
    @calls = []
  end

  def command(verb, *argv, status: 0, env: {})
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments|
      @calls << [path, arguments]
      status
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
