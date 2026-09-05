require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
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

  # --- item 8 (post-execution review): the plain-wording convention for
  # ## Delivered rows must land where outcome.md is authored, not in the
  # reader (D14: the reader renders its source; the source is where the
  # ruling belongs).

  def test_outcome_template_states_the_plain_wording_convention_for_delivered_rows
    text = File.read(File.join(REPO, "templates", "outcome.md"))
    delivered_idx = text.index("## Delivered")
    verification_idx = text.index("## Verification")
    refute_nil delivered_idx
    refute_nil verification_idx
    section = text[delivered_idx...verification_idx]
    assert_includes section, "plain wording"
    assert_includes section, "## Summary"
  end

  def test_intent_ending_skill_states_the_plain_wording_convention
    text = File.read(File.join(REPO, "skills", "intent-ending", "SKILL.md"))
    assert_includes text, "plain wording"
    assert text.lines.length <= 300, "skills/intent-ending/SKILL.md must stay at or under 300 lines"
  end

  # --- row 82/83: core_files registers the two new scripts ---------------------

  def test_core_files_registers_report_screen
    assert_includes core_lib, %("scripts/report-screen")
  end

  def test_core_files_registers_savepoint_note
    assert_includes core_lib, %("scripts/savepoint-note")
  end

  # 317a S14 (B1): the painter lib ships, or report-screen --ansi and the
  # MessageDisplay hook LoadError on every real install.
  def test_core_files_registers_screen_paint
    assert_includes core_lib, %("scripts/lib/screen_paint.rb")
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

  # --- item 9 (owner ruling 2026-08-31): the TUI delivery is cross-harness.
  # ANSI selection is by capability (--ansi flag, NO_COLOR, TTY), never by
  # harness name; a Claude-only branch here would be the regression this
  # ruling targets. Crude but exact: no source file names a harness.

  def test_no_source_file_branches_on_a_harness_name
    %w[
      scripts/lib/report_screen.rb
      scripts/report-screen
      scripts/savepoint-note
      templates/report-state.md
      templates/report-roadmap-plan.md
      templates/report-roadmap-state.md
      templates/report-roadmap-delivered.md
      scripts/lib/screens/roadmap.rb
    ].each do |rel|
      text = File.read(File.join(REPO, rel))
      refute_match(/claude|codex/i, text, "#{rel} must not name a harness (ANSI selection is by capability, not by name)")
    end
  end

  # --- 317a S6 (matrix S6a): the template writes the labeled-table shape the
  # readers consume; 317 shipped a template that guaranteed "not recorded".

  def test_outcome_template_delivered_is_a_labeled_table
    text = File.read(File.join(REPO, "templates", "outcome.md"))
    section = text[text.index("## Delivered")...text.index("## Verification")]
    assert_includes section, "| Row | What |"
    assert_includes section, "standalone token"
    assert_includes section, "Proven-by"
  end

  def test_outcome_template_needs_you_names_the_table_shape
    text = File.read(File.join(REPO, "templates", "outcome.md"))
    section = text[text.index("## Needs you")...text.index("## Follow-ups")]
    assert_includes section, "| N | What | Why |"
    assert_includes section, "None"
  end

  # --- intent 331a (D6, R7/R8): scripts/lib/screens/*.rb ships, and
  # report-screen tolerates its absence ---------------------------------------

  # R7: a file under scripts/lib/screens/ must reach an installed ~/.plastic.
  # Behavioral, not a source scan: the mechanism is a glob, so a fixture
  # package_root with a fake kind file proves InstallerCore#core_files picks
  # it up without any hand-written entry naming that file.
  def test_screens_dir_is_glob_registered_for_install
    Dir.mktmpdir("screens-glob-pkg-331a") do |fake_root|
      screens_dir = File.join(fake_root, "scripts", "lib", "screens")
      FileUtils.mkdir_p(screens_dir)
      File.write(File.join(screens_dir, "demo.rb"), "# demo kind\n")

      installer = InstallerCore.new(package_root: fake_root,
                                     plastic_home: Dir.mktmpdir("screens-glob-home-331a"),
                                     version: "1.0.0-test")
      assert_includes installer.core_files.keys, "scripts/lib/screens/demo.rb"
    end
  end

  # R8: report-screen glob-requires scripts/lib/screens/*.rb and must not
  # raise when that directory is absent or empty (this repo has none yet).
  def test_report_screen_glob_requires_screens_and_tolerates_an_empty_dir
    src = File.read(File.join(REPO, "scripts", "report-screen"))
    assert_includes src, %(Dir.glob(File.join(__dir__, "lib", "screens", "*.rb")))

    out, err, status = Open3.capture3("ruby", File.join(REPO, "scripts", "report-screen"))
    assert_equal 2, status.exitstatus, "a bare invocation is a usage error, not a crash"
    refute_includes err, "LoadError"
    assert_empty out
  end

end
