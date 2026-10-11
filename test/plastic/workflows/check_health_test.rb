# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../doctor/whole_home"
require_relative "../../../scripts/lib/plastic/workflows/check_health"

class CheckHealthTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  GATE = "code_check_health, gate: a check found a problem; run the repairs named above, then run plastic doctor again"

  def setup
    super
    whole_home
  end

  def check(env = { "CLAUDE_CODE_SESSION_ID" => "s-1" }, session: "s-1")
    harness = scoped_harness(session:, env: { "PLASTIC_PACKAGE_ROOT" => fake_package(RUNNING) }.merge(env))
    run_workflow(Plastic::Workflows::CheckHealth, harness:, harness_name: nil)
  end

  def test_a_whole_home_is_done_with_no_repair
    outcome, context = check

    assert_equal [:done, nil], [outcome, printed_row(context, "repair:")]
  end

  def test_each_check_prints_one_row
    _outcome, context = check

    assert_equal "version:", printed_rows(context).first.first
  end

  def test_a_finding_fails_at_the_gate
    File.delete(machine_path)

    assert_equal GATE, check.first.message
  end

  def test_the_repairs_print_as_one_row_with_one_line_each
    File.delete(machine_path)
    File.chmod(0o644, hook_file)

    assert_equal ["plastic install --reinstall", "plastic install --reinstall"], printed_row(check.last, "repair:")
  end

  def test_a_codex_session_with_no_install_reports_the_missing_record
    outcome, context = check({ "CODEX_THREAD_ID" => "t-1" }, session: "t-1")

    assert_equal GATE, outcome.message
    assert_includes printed_row(context, "codex record:"), "no installation record"
  end
end
