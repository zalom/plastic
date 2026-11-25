# frozen_string_literal: true

require_relative "recording_helper"

class InstallationsRecordingTest < Plastic::TestCase
  include RecordingHelper

  MINE = { "type" => "command", "command" => "mine" }.freeze

  def claude_settings = File.join(@home, ".claude", "settings.json")

  def own_settings(settings)
    FileUtils.mkdir_p(File.join(@home, ".claude"))
    File.write(claude_settings, JSON.generate(settings))
  end

  def test_the_record_lists_every_file_of_the_manifest_and_the_manifest
    own_settings({})
    installed_into("claude")
    manifest = File.join(@home, ".claude", "plastic", "manifest.json")

    assert_equal JSON.parse(File.read(manifest))["files"].keys + [manifest], recorded("claude-code").files
  end

  def test_the_record_lists_the_plastic_folders_the_files_live_in
    own_settings({})
    installed_into("claude")
    folders = recorded("claude-code").folders

    assert_includes folders, File.join(@home, ".claude", "plastic")
    refute_includes folders, File.join(@home, ".claude", "agents")
  end

  def test_the_record_lists_the_plastic_hook_entries_and_not_the_persons_own
    own_settings("hooks" => { "Stop" => [{ "hooks" => [{ "type" => "command", "command" => "my-stop" }] }] })
    installed_into("claude")
    hooks = recorded("claude-code").hooks

    assert_equal %w[PreToolUse SessionEnd SessionStart Stop UserPromptSubmit], hooks.map { |entry| entry["event"] }.uniq.sort
    refute_includes hooks.map { |entry| entry["command"] }, "my-stop"
  end

  def test_the_record_lists_the_deny_entry_an_earlier_install_wrote_for_the_scripts_folder
    own_settings({})
    installed_into("claude")
    File.write(claude_settings, JSON.generate("permissions" => { "deny" => ["Edit(~/.plastic/scripts/**)", "Edit(~/mine/**)"] }))

    assert_equal ["Edit(~/.plastic/scripts/**)"], recorded("claude-code").permissions
  end

  def test_the_record_keeps_the_status_line_plastic_replaced
    own_settings("statusLine" => MINE)
    call("config", "set", "statusline", "true")
    installed_into("claude", statusline: :plastic)
    status_line = recorded("claude-code").status_line

    assert_equal MINE, status_line["replaced"]
    assert_equal JSON.parse(File.read(claude_settings)).dig("statusLine", "command"), status_line["command"]
  end

  def test_the_record_lists_the_deny_entries_plastic_added_and_not_the_persons_own
    own_settings("permissions" => { "deny" => ["Edit(~/mine/**)"] })
    installed_into("claude")

    assert_equal Plastic::Installations::EnginePermissions::ENTRIES, recorded("claude-code").permissions
  end
end

class InstallationsRecordingCodexTest < Plastic::TestCase
  include RecordingHelper

  def setup
    super
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    installed_into("codex")
  end

  def test_the_record_lists_the_marked_section_of_the_instruction_file
    section = recorded("codex").sections.first

    assert_equal [File.join(@home, ".codex", "AGENTS.md"), "<!-- BEGIN PLASTIC INTEGRATION"], section.values_at("file", "begin")
  end

  def test_the_codex_record_names_the_hooks_file_and_no_status_line
    record = recorded("codex")

    assert_equal [File.join(@home, ".codex", "hooks.json"), nil, []], [record.settings, record.status_line, record.permissions]
  end

  def test_the_record_lists_no_section_when_the_instruction_file_is_gone
    File.delete(File.join(@home, ".codex", "AGENTS.md"))

    assert_empty recorded("codex").sections
  end
end

class InstallationsRecordingHermesTest < Plastic::TestCase
  include RecordingHelper

  def setup
    super
    FileUtils.mkdir_p(File.join(@home, ".hermes"))
    installed_into("hermes")
  end

  def test_the_hermes_record_lists_the_skills_and_agents_it_copied
    files = recorded("hermes").files

    assert_includes files, File.join(@home, ".hermes", "plastic", "VERSION")
    assert(files.any? { |file| file.start_with?(File.join(@home, ".hermes", "agents", "plastic-")) })
  end

  def test_the_hermes_record_names_no_settings_file_and_no_section
    record = recorded("hermes")

    assert_equal [nil, [], nil, [], []], [record.settings, record.hooks, record.status_line, record.permissions, record.sections]
  end
end
