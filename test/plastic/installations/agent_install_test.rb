# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/package"
require "plastic/installations/agent_set"
require "plastic/installations/claude_install"
require "plastic/installations/codex_install"
require "plastic/installations/hermes_install"

class ClaudeInstallTest < Plastic::TestCase
  include InstallFixture

  Installations = Plastic::Installations

  def install(statusline: nil)
    result = nil
    out, = capture_io { result = Installations::ClaudeInstall.new(shipped_package, Installations::AgentRecord.new(claude_config), statusline:).call }
    [result, out]
  end

  def claude(*parts) = File.join(fresh, ".claude", *parts)

  def test_a_hook_is_copied_with_the_plastic_prefix_the_script_path_rewritten_and_the_mode_executable
    install
    hook = claude("hooks", "plastic-session-start")

    assert_equal [true, true], [File.read(hook).include?("$HOME/.plastic/scripts/lib/x"), File.executable?(hook)]
  end

  def test_the_status_line_hook_is_left_out_while_the_flag_is_off_and_an_old_copy_is_removed
    write(claude("hooks", "plastic-statusline"), "old\n")
    _, out = install

    refute_path_exists claude("hooks", "plastic-statusline")
    assert_includes out, "  Status line removed. To turn it on: plastic config set statusline true\n"
  end

  def test_the_status_line_hook_is_copied_while_the_flag_is_on
    config_with("global:\n  statusline: true\n")
    install

    assert_path_exists claude("hooks", "plastic-statusline")
  end

  def test_the_skills_the_roles_the_version_and_the_manifest_are_written
    result, = install
    manifest = JSON.parse(File.read(claude("plastic", "manifest.json")))["files"].keys

    assert_equal [true, true, "2.0.3\n"], [manifest.include?(claude("skills", "plastic-demo", "SKILL.md")), manifest.include?(claude("agents", "demo-role.md")),
      File.read(claude("plastic", "VERSION"))]
    assert_equal({ agent: "Claude Code", success: true, files: manifest.size - 1 }, result.merge(files: result[:files] - 1))
  end

  def test_a_declined_advisor_leaves_out_the_advisor_skill
    config_with("global:\n  advisor:\n    enabled: false\n")
    install

    refute_path_exists claude("skills", "plastic-agent-advisor")
  end

  def test_the_settings_gain_the_hooks_and_the_deny_rules_and_the_instruction_file_gains_its_section
    install

    assert_equal [true, true, true],
      [JSON.parse(File.read(claude("settings.json"))).key?("hooks"), File.read(claude("settings.json")).include?("Edit(~/.plastic/hooks/**)"),
        File.read(claude("CLAUDE.md")).include?("<!-- BEGIN PLASTIC COMPACT")]
  end

  def test_a_legacy_plugin_layout_is_removed
    write(claude("skills", "plastic", "old.md"), "old\n")
    install

    refute_path_exists claude("skills", "plastic")
  end

  def test_a_status_line_of_the_person_stays_unless_they_chose_plastic_with_the_flag_on
    config_with("global:\n  statusline: true\n")
    write(claude("settings.json"), JSON.generate("statusLine" => { "type" => "command", "command" => "mine" }))
    install

    assert_equal "mine", JSON.parse(File.read(claude("settings.json"))).dig("statusLine", "command")
    install(statusline: :plastic)

    assert_equal claude("hooks", "plastic-statusline"), JSON.parse(File.read(claude("settings.json"))).dig("statusLine", "command")
  end

  def test_a_status_line_that_plastic_wrote_is_replaced_without_asking
    config_with("global:\n  statusline: true\n")
    write(claude("settings.json"), JSON.generate("statusLine" => { "type" => "command", "command" => claude("hooks", "plastic-statusline") }))
    install

    assert_equal claude("hooks", "plastic-statusline"), JSON.parse(File.read(claude("settings.json"))).dig("statusLine", "command")
  end
end

class CodexInstallTest < Plastic::TestCase
  include InstallFixture

  Installations = Plastic::Installations

  def install(root = nil)
    package = root ? Installations::Package.new(root, plastic, "2.0.3") : shipped_package
    result = nil
    capture_io { result = Installations::CodexInstall.new(package, Installations::AgentRecord.new(codex_config)).call }
    result
  end

  def test_each_role_is_written_as_toml_and_the_version_is_recorded
    result = install

    assert_equal [true, true, true], [result[:success], File.exist?(File.join(fresh, ".codex", "agents", "demo-role.toml")),
      File.exist?(File.join(fresh, ".agents", "plastic", "VERSION"))]
  end

  def test_the_skills_land_in_the_shared_agents_folder_and_the_section_in_the_codex_instructions
    install

    assert_equal [true, true], [File.exist?(File.join(fresh, ".agents", "skills", "plastic-demo", "SKILL.md")),
      File.read(File.join(fresh, ".codex", "AGENTS.md")).include?("<!-- BEGIN PLASTIC INTEGRATION")]
  end

  def test_a_package_with_no_skills_folder_writes_no_skills
    root = File.join(@home, "bare")
    write(File.join(root, "VERSION"), "2.0.3\n")
    install(root)

    refute_path_exists File.join(fresh, ".agents", "skills")
  end

  def test_the_install_names_the_hooks_it_changed_and_a_second_one_changes_none
    assert_equal ["hook end", "hook start", "hook stop"], install[:changed_hooks].sort
    assert_empty install[:changed_hooks]
  end
end

class HermesInstallTest < Plastic::TestCase
  include InstallFixture

  def test_the_skills_the_roles_the_version_and_the_manifest_are_written
    record = Plastic::Installations::AgentRecord.new(hermes_config)
    result = Plastic::Installations::HermesInstall.new(shipped_package, record).call

    assert_equal [true, true, "2.0.3\n", true],
      [File.exist?(File.join(fresh, ".hermes", "skills", "plastic-demo", "SKILL.md")), File.exist?(File.join(fresh, ".hermes", "agents", "demo-role.md")),
        File.read(File.join(fresh, ".hermes", "plastic", "VERSION")), result[:success]]
  end
end
