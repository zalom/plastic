# frozen_string_literal: true

require_relative "doctor/whole_home"
require_relative "../../scripts/lib/plastic/doctor"

class DoctorTest < Plastic::TestCase
  include WholeHome

  class Other
    def initialize(_scope, running:) = @running = running

    def checks = [Plastic::Doctor::Check.ok("other:", @running)]
  end

  def seed(harness)
    Plastic::Graph::Database::Local.new(@plastic_home).transaction do |batch|
      batch.put(:sessions, { session_id: "s-1", harness:, started_at: STAMP })
    end
  end

  def test_the_harness_on_the_session_row_is_checked
    seed("codex")

    assert_equal "codex", Plastic::Doctor.harness(scope("CLAUDE_CODE_SESSION_ID" => "s-1"), session: "s-1")
  end

  def test_a_session_variable_equal_to_the_session_names_its_harness
    assert_equal "codex", Plastic::Doctor.harness(scope("CODEX_THREAD_ID" => "t-1"), session: "t-1")
  end

  def test_a_row_of_an_unregistered_harness_falls_back_to_the_variables
    seed("unknown")

    assert_equal "claude-code", Plastic::Doctor.harness(scope("CLAUDE_CODE_SESSION_ID" => "s-1"), session: "s-1")
  end

  def test_nothing_naming_a_harness_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Doctor.harness(scope, session: nil) }

    assert_equal "no harness names this call; name one with --harness: claude-code, codex", error.message
  end

  def test_a_harness_with_no_module_is_a_usage_error_naming_the_ones_that_have_one
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Doctor.kind("unknown") }

    assert_equal "no doctor for the harness unknown; harnesses with one: claude-code, codex", error.message
  end

  def test_a_registered_harness_that_declares_no_doctor_has_none
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Doctor.kind("hermes") }

    assert_equal "no doctor for the harness hermes; harnesses with one: claude-code, codex", error.message
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

  def test_a_broken_home_names_repair_commands_and_never_plastic_next
    repairs = Plastic::Doctor.run(scope, harness: "claude-code").filter_map(&:repair).uniq

    refute_empty repairs
    refute(repairs.any? { |repair| repair.include?("plastic next") })
  end
end
