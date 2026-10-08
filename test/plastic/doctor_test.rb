# frozen_string_literal: true

require_relative "doctor/whole_home"
require_relative "../../scripts/lib/plastic/doctor"

class DoctorTest < Plastic::TestCase
  include WholeHome

  class Other
    def initialize(_scope, running:) = @running = running

    def checks = [Plastic::Doctor::Check.ok("other:", @running)]
  end

  def test_a_call_with_no_codex_variable_checks_claude_code
    assert_equal "claude-code", Plastic::Doctor.harness(scope)
  end

  def test_a_codex_variable_picks_codex
    assert_equal "codex", Plastic::Doctor.harness(scope("CODEX_THREAD_ID" => "t-1"))
  end

  def test_a_harness_with_no_module_is_a_usage_error_naming_the_ones_that_have_one
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Doctor.kind("unknown") }

    assert_equal "no doctor for the harness unknown; harnesses with one: claude-code, codex", error.message
  end

  def test_a_module_passed_beside_claude_code_is_found_by_name
    kind = Plastic::Doctor.kind("other", Plastic::Doctor::HARNESSES.merge("other" => Other))
    checks = Plastic::Doctor.checks(scope, kind, running: RUNNING)

    assert_equal ["other:", "ok, #{RUNNING}"], checks.last.to_a.first(2)
  end

  def test_the_core_checks_come_first_for_every_harness
    checks = Plastic::Doctor.checks(scope, Plastic::Doctor.kind("claude-code"), running: RUNNING)

    assert_equal "version:", checks.first.label
  end
end
