require "minitest/autorun"
require_relative "../scripts/lib/installer_core"

# Intent 317, D11/D17: templates/outcome.md gains ## Needs you; the installer
# registers the two new scripts plus the shared module (the insight-append
# precedent, intent 151); the docs learn the new savepoint kinds; both new
# scripts install executable.
class ReportScreenPackagingTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def core_lib
    @core_lib ||= File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
  end

  # --- row 81: outcome.md template gains ## Needs you, before Follow-ups ------

  def test_outcome_template_gains_needs_you_before_follow_ups
    text = File.read(File.join(REPO, "templates", "outcome.md"))
    assert_includes text, "## Needs you"
    needs_idx = text.index("## Needs you")
    followups_idx = text.index("## Follow-ups")
    refute_nil followups_idx
    assert needs_idx < followups_idx
    section = text[needs_idx...followups_idx]
    assert_includes section, "None"
  end

  # --- row 82/83: core_files registers the two new scripts ---------------------

  def test_core_files_registers_report_screen
    assert_includes core_lib, %("scripts/report-screen")
  end

  def test_core_files_registers_savepoint_note
    assert_includes core_lib, %("scripts/savepoint-note")
  end

  # --- row 84 [guard]: the script installs with its module ---------------------

  def test_core_files_registers_report_screen_lib
    assert_includes core_lib, %("scripts/lib/report_screen.rb")
  end

  # --- row 85: reading-the-ledgers.md names the new kinds -----------------------

  def test_reading_the_ledgers_names_review_and_commit
    text = File.read(File.join(REPO, "docs", "guides", "reading-the-ledgers.md"))
    assert_includes text, "Review"
    assert_includes text, "Commit"
    refute_includes text, "The stage names are What, Why, How, and Exec."
  end

  # --- row 86: executable bit ---------------------------------------------------

  def test_new_scripts_are_executable
    %w[scripts/report-screen scripts/savepoint-note].each do |rel|
      path = File.join(REPO, rel)
      assert File.exist?(path), "#{rel} is missing"
      mode = File.stat(path).mode & 0o777
      assert_equal 0o755, mode, "#{rel} must install executable (0755), got #{mode.to_s(8)}"
    end
  end
end
