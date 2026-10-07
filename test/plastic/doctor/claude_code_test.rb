# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorClaudeCodeTest < Plastic::TestCase
  include WholeHome

  def setup
    super
    whole_home
  end

  def checks(running: RUNNING) = Plastic::Doctor::ClaudeCode.new(scope, running:).checks

  def check(label, **options) = checks(**options).find { |item| item.label == label }

  def test_a_whole_claude_folder_has_no_finding
    assert_empty checks.filter_map(&:repair), checks.map(&:to_h).inspect
  end

  def test_the_checks_cover_the_record_the_hooks_and_the_instruction_files
    labels = ["claude record:", "hook SessionStart:", "hook Stop:", "hook SessionEnd:", "CLAUDE.md:", "CLAUDE.md #{SLUG}:"]

    assert_equal labels, checks.map(&:label)
  end

  def test_a_stale_claude_record_names_the_claude_reinstall
    assert_equal "plastic install --claude --reinstall", check("claude record:", running: "9.2.0").repair
  end

  def test_a_missing_claude_record_names_the_claude_install
    File.delete(File.join(claude_dir, "plastic", "VERSION"))

    assert_equal "plastic install --claude", check("claude record:").repair
  end

  def test_a_claude_md_without_the_import_line_names_the_claude_reinstall
    write(File.join(claude_dir, "CLAUDE.md"), "# Mine\n")

    assert_equal "plastic install --claude --reinstall", check("CLAUDE.md:").repair
  end

  def test_a_project_claude_md_without_the_agents_import_names_the_edit
    claude_md = File.join(project_dir, "CLAUDE.md")
    write(claude_md, "# Alpha\n\nRead AGENTS.md.\n")

    assert_equal "add the line @AGENTS.md to #{claude_md}", check("CLAUDE.md #{SLUG}:").repair
  end
end
