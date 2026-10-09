# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/resume"
require_relative "../../../scripts/lib/plastic/doctor/check"

class ResumeDoctorTest < Plastic::TestCase
  fixtures :empty

  Check = Plastic::Doctor::Check

  PASSING = ->(_scope) { [] }
  FAILING = ->(_scope) { [Check.new("launcher:", "missing", "run plastic install --reinstall"), Check.new("hooks:", "stale", "run plastic init")] }
  BROKEN = ->(_scope) { raise "the doctor broke" }

  def resume(health)
    out = StringIO.new
    err = StringIO.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new("{}"), out:, err:, home: @home, directory: @home)
    code = Plastic::Hooks::Resume.call([], environment:, health:)
    [code, out.string, err.string]
  end

  def test_a_failing_check_adds_one_line_that_names_plastic_doctor
    code, out, err = resume(FAILING)

    assert_equal [0, ""], [code, err]
    assert_equal ["Plastic: doctor found 2 failing checks; run plastic doctor."], out.lines(chomp: true).grep(/doctor/)
    assert_match(/\APlastic: a new session in store global\./, out)
  end

  def test_every_check_passing_prints_nothing_about_doctor
    code, out, err = resume(PASSING)

    assert_equal [0, ""], [code, err]
    refute_match(/doctor/i, out)
  end

  def test_a_doctor_that_breaks_still_prints_the_recap_and_exits_0
    code, out, err = resume(BROKEN)

    assert_equal 0, code
    assert_match(/\APlastic: a new session/, out)
    assert_equal "plastic hook: the doctor broke\n", err
  end
end

class ResumeDoctorMissingStoreTest < Plastic::TestCase
  def test_a_missing_store_stays_quiet_and_never_runs_the_doctor
    with_home(global: false) do |home|
      out = StringIO.new
      err = StringIO.new
      asked = []
      environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => home, "PLASTIC_SESSION" => "s-1" },
        input: StringIO.new("{}"), out:, err:, home: File.dirname(home), directory: File.dirname(home))

      code = Plastic::Hooks::Resume.call([], environment:, health: ->(scope) { asked << scope && [] })

      assert_equal [0, "", "", []], [code, out.string, err.string, asked]
    end
  end
end
