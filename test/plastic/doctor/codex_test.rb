# frozen_string_literal: true

require_relative "codex_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorCodexTest < Plastic::TestCase
  include CodexHome

  def setup
    super
    whole_codex
  end

  def checks(env = {}) = Plastic::Doctor::Codex.new(scope(env), running: RUNNING).checks

  def check(label) = checks.find { |item| item.label == label }

  def test_a_complete_codex_install_has_no_repairs_without_any_claude_files
    FileUtils.rm_rf(claude_dir)
    File.delete(File.join(project_dir, "CLAUDE.md"))

    assert_empty checks.filter_map(&:repair)
  end

  def test_a_missing_record_names_init
    File.delete(codex_record)

    assert_equal "plastic init", check("codex record:").repair
  end

  def test_a_stale_record_names_the_reinstall
    write(codex_record, "0.0.1\n")

    assert_equal "plastic install --reinstall", check("codex record:").repair
  end

  def test_missing_codex_instructions_name_the_reinstall
    File.delete(File.join(codex_dir, "AGENTS.md"))

    assert_equal "plastic install --reinstall", check("Codex AGENTS.md:").repair
  end

  def test_a_custom_codex_home_is_reported_because_the_installer_uses_dot_codex
    found = checks("CODEX_HOME" => File.join(@home, "elsewhere")).find { |item| item.label == "CODEX_HOME:" }

    assert_includes found.value, "installer"
    assert_includes found.repair, "CODEX_HOME"
  end

  def test_hook_trust_is_explicitly_unverified_and_does_not_fail_file_checks
    trust = check("hook trust:")

    assert_nil trust.repair
    assert_includes trust.value, "not verified"
    assert_includes trust.value, "/hooks"
  end
end
