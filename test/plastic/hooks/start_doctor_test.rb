# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/start"
require_relative "../../../scripts/lib/plastic/doctor/check"

class StartDoctorTest < Plastic::TestCase
  fixtures :empty

  Check = Plastic::Doctor::Check

  PASSING = ->(_scope, _harness) { [] }
  FAILING = ->(_scope, _harness) { [Check.new("launcher:", "missing", "run plastic install --reinstall"), Check.new("hooks:", "stale", "run plastic init")] }
  BROKEN = ->(_scope, _harness) { raise "the doctor broke" }

  CLAUDE = "/u/.claude/projects/p/s-1.jsonl"

  def resume(health, source: nil, transcript_path: CLAUDE)
    out = StringIO.new
    err = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new(JSON.generate({ source:, transcript_path: }.compact)), out:, err:, home: @home, directory: @home)
    code = Plastic::Hooks::Start.call([], environment:, health:)
    [code, out.string, err.string]
  end

  def test_a_failing_check_adds_one_line_that_names_plastic_doctor
    code, out, err = resume(FAILING)

    assert_equal [0, ""], [code, err]
    assert_equal ["Plastic: doctor found 2 failing checks; run plastic doctor."], out.lines(chomp: true).grep(/doctor/)
    assert_match(/\APlastic: a new session in store global\./, out)
  end

  def test_one_failing_check_is_named_as_one_check
    _code, out, _err = resume(->(_scope, _harness) { [Check.new("hooks:", "stale", "run plastic init")] })

    assert_equal ["Plastic: doctor found 1 failing check; run plastic doctor."], out.lines(chomp: true).grep(/doctor/)
  end

  def test_a_session_that_starts_fresh_runs_the_doctor
    _code, out, _err = resume(FAILING, source: "startup")

    assert_equal 1, out.lines.grep(/doctor found/).size
  end

  def test_a_resumed_compacted_or_cleared_session_never_runs_the_doctor
    lines = %w[resume compact clear].flat_map { |source| resume(FAILING, source:)[1].lines.grep(/doctor/) }

    assert_empty lines
  end

  def test_the_doctor_checks_the_harness_the_start_detected
    asked = []
    resume(->(_scope, harness) { asked << harness && [] }, transcript_path: "/u/.codex/sessions/r.jsonl")

    assert_equal ["codex"], asked
  end

  def test_a_start_no_harness_names_runs_no_doctor
    asked = []
    resume(->(_scope, harness) { asked << harness && [] }, transcript_path: nil)

    assert_empty asked
  end

  def test_every_check_passing_prints_nothing_about_doctor
    code, out, err = resume(PASSING)

    assert_equal [0, "Plastic: a new session in store global. Run plastic next before anything else.\n", ""], [code, out, err]
  end

  def test_a_doctor_that_breaks_still_prints_the_recap_and_exits_0
    code, out, err = resume(BROKEN)

    assert_equal 0, code
    assert_match(/\APlastic: a new session/, out)
    assert_equal "plastic hook: the doctor broke\n", err
  end
end

class StartDoctorMissingStoreTest < Plastic::TestCase
  def test_a_missing_store_stays_quiet_and_never_runs_the_doctor
    with_home(global: false) do |home|
      out = StringIO.new
      err = StringIO.new
      asked = []
      environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => home, "PLASTIC_SESSION" => "s-1" },
        input: StringIO.new("{}"), out:, err:, home: File.dirname(home), directory: File.dirname(home))

      code = Plastic::Hooks::Start.call([], environment:, health: ->(scope, _harness) { asked << scope && [] })

      assert_equal [0, "", "", []], [code, out.string, err.string, asked]
    end
  end
end

require_relative "../commands/installer_helper"
require_relative "../doctor/whole_home"

class StartHealthyHomeTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  def setup
    super
    whole_home
    @package = fake_package(RUNNING)
  end

  def test_an_installed_healthy_home_gives_no_doctor_line
    env = { "PLASTIC_PACKAGE_ROOT" => @package, "CLAUDE_CODE_SESSION_ID" => "s-1" }
    doctor = call("doctor", env:)
    resume = call("hook", "start", env:)

    assert_equal [0, 0, ""], [doctor.code, resume.code, resume.err]
    assert_match(/\APlastic: a new session/, resume.out)
    refute_match(/doctor/i, resume.out)
  end
end
