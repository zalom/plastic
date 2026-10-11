# frozen_string_literal: true

require "stringio"
require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation"
require_relative "../../../scripts/lib/plastic/installations"

class InstallationsRecordingTest < Plastic::TestCase
  include InstallerHelper

  MINE = { "type" => "command", "command" => "mine" }.freeze

  def installation = Plastic::Workflows::Installation.of(call_context(harness: scoped_harness))

  def installed_into(key)
    Plastic::Workflows::Installation.capture { installation.run(selected: [key], argv: [], input: StringIO.new) }
  end

  def recorded(name) = Plastic::Installations::Recording.new(installation, Plastic::Harnesses.fetch(name)).call

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

    assert_equal %w[SessionEnd SessionStart Stop], hooks.map { |entry| entry["event"] }.uniq.sort
    refute_includes hooks.map { |entry| entry["command"] }, "my-stop"
  end

  def test_the_record_keeps_the_status_line_plastic_replaced
    own_settings("statusLine" => MINE)
    installed_into("claude")
    status_line = recorded("claude-code").status_line

    assert_equal MINE, status_line["replaced"]
    assert_equal JSON.parse(File.read(claude_settings)).dig("statusLine", "command"), status_line["command"]
  end

  def test_the_record_lists_the_deny_entries_plastic_added_and_not_the_persons_own
    own_settings("permissions" => { "deny" => ["Edit(~/mine/**)"] })
    installed_into("claude")

    assert_equal EnginePermissions::ENTRIES, recorded("claude-code").permissions
  end

  def test_the_record_lists_the_marked_section_of_the_instruction_file
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    installed_into("codex")
    section = recorded("codex").sections.first

    assert_equal [File.join(@home, ".codex", "AGENTS.md"), "<!-- BEGIN PLASTIC INTEGRATION"], section.values_at("file", "begin")
  end

  def test_the_codex_record_names_the_hooks_file_and_no_status_line
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    installed_into("codex")
    record = recorded("codex")

    assert_equal [File.join(@home, ".codex", "hooks.json"), nil, []], [record.settings, record.status_line, record.permissions]
  end
end
