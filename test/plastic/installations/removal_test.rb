# frozen_string_literal: true

require "json"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/installations"

class InstallationsRemovalTest < Plastic::TestCase
  PLASTIC = "plastic hook start"
  MINE = "my-start"

  def folder = File.join(@home, ".claude")

  def settings_path = File.join(folder, "settings.json")

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def record(**parts)
    Plastic::Installations::Record.new(harness: "claude-code", version: "2.0.5", roots: [folder], files: [], folders: [],
      settings: settings_path, hooks: [], status_line: nil, permissions: [], sections: [], **parts)
  end

  def removed(record)
    Plastic::Installations.write(@plastic_home, record)
    Plastic::Installations::Removal.new(record, plastic_home: @plastic_home).call
  end

  def settings = JSON.parse(File.read(settings_path))

  def hook(command) = { "hooks" => [{ "type" => "command", "command" => command }] }

  def test_removes_the_listed_files_and_the_emptied_plastic_folders
    file = write(File.join(folder, "skills", "plastic-x", "SKILL.md"), "x")
    removed(record(files: [file], folders: [File.dirname(file)]))

    assert_equal [false, true], [File.exist?(File.dirname(file)), File.directory?(File.join(folder, "skills"))]
  end

  def test_keeps_a_listed_folder_that_holds_a_file_of_the_person
    file = write(File.join(folder, "plastic", "VERSION"), "2.0.5")
    write(File.join(folder, "plastic", "mine.md"), "mine")
    removed(record(files: [file], folders: [File.dirname(file)]))

    assert_path_exists File.join(folder, "plastic", "mine.md")
  end

  def test_never_removes_a_listed_file_outside_the_harness_folders
    outside = write(File.join(@home, "notes.md"), "mine")
    removed(record(files: [outside]))

    assert_path_exists outside
  end

  def test_removes_the_listed_hook_entries_and_keeps_the_persons_own
    write(settings_path, JSON.generate("hooks" => { "SessionStart" => [hook(PLASTIC), hook(MINE)], "Stop" => [hook(PLASTIC)] }))
    removed(record(hooks: [{ "event" => "SessionStart", "command" => PLASTIC }, { "event" => "Stop", "command" => PLASTIC }]))

    assert_equal({ "SessionStart" => [hook(MINE)] }, settings["hooks"])
  end

  def test_keeps_an_entry_that_runs_plastic_when_the_record_does_not_list_it
    write(settings_path, JSON.generate("hooks" => { "Stop" => [hook(PLASTIC)] }, "model" => "opus"))
    removed(record(hooks: [{ "event" => "SessionStart", "command" => PLASTIC }]))

    assert_equal({ "Stop" => [hook(PLASTIC)] }, settings["hooks"])
  end

  def test_restores_the_status_line_plastic_replaced
    write(settings_path, JSON.generate("statusLine" => { "type" => "command", "command" => "plastic-statusline" }))
    removed(record(status_line: { "command" => "plastic-statusline", "replaced" => { "type" => "command", "command" => "mine" } }))

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  def test_keeps_a_status_line_the_person_set_after_the_install
    write(settings_path, JSON.generate("statusLine" => { "type" => "command", "command" => "mine" }))
    removed(record(status_line: { "command" => "plastic-statusline", "replaced" => nil }))

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  def test_removes_the_listed_deny_entries_and_keeps_the_persons_own
    write(settings_path, JSON.generate("permissions" => { "deny" => ["Edit(~/.plastic/hooks/**)", "Edit(~/mine/**)"] }))
    removed(record(permissions: ["Edit(~/.plastic/hooks/**)"]))

    assert_equal ["Edit(~/mine/**)"], settings.dig("permissions", "deny")
  end

  def test_deletes_a_settings_file_that_held_only_plastic_entries
    write(settings_path, JSON.generate("hooks" => { "Stop" => [hook(PLASTIC)] }))
    removed(record(hooks: [{ "event" => "Stop", "command" => PLASTIC }]))

    refute_path_exists settings_path
  end

  def test_strips_the_marked_section_and_keeps_the_persons_text
    section = "<!-- BEGIN PLASTIC COMPACT hash:abc -->\nbody\n<!-- END PLASTIC COMPACT -->\n"
    path = write(File.join(folder, "CLAUDE.md"), "# Mine\n\n#{section}")
    removed(record(sections: [{ "file" => path, "begin" => "<!-- BEGIN PLASTIC COMPACT", "end" => "<!-- END PLASTIC COMPACT -->" }]))

    assert_equal "# Mine\n", File.read(path)
  end

  def test_deletes_an_instruction_file_that_held_only_the_section
    path = write(File.join(folder, "CLAUDE.md"), "<!-- BEGIN PLASTIC COMPACT hash:abc -->\nbody\n<!-- END PLASTIC COMPACT -->\n")
    removed(record(sections: [{ "file" => path, "begin" => "<!-- BEGIN PLASTIC COMPACT", "end" => "<!-- END PLASTIC COMPACT -->" }]))

    refute_path_exists path
  end

  def test_deletes_the_record_and_names_each_path_it_removed
    file = write(File.join(folder, "plastic", "VERSION"), "2.0.5")
    paths = removed(record(files: [file]))

    assert_equal [nil, [file]], [Plastic::Installations.read(@plastic_home, "claude-code"), paths]
  end
end
