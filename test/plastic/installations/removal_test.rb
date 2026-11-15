# frozen_string_literal: true

require_relative "../../support/removal_fixture"

class InstallationsRemovalTest < Plastic::TestCase
  include RemovalFixture

  def test_removes_the_listed_files_and_the_emptied_plastic_folders
    file = write(File.join(folder, "skills", "plastic-x", "SKILL.md"), "x")
    removed(record(files: [file], folders: [File.dirname(file)]))

    assert_equal [false, false], [File.exist?(File.dirname(file)), File.directory?(File.join(folder, "skills"))]
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
    path = write(File.join(folder, "CLAUDE.md"), "# Mine\n\n#{SECTION}")
    removed(record(sections: [section_for(path)]))

    assert_equal "# Mine\n", File.read(path)
  end

  def test_deletes_an_instruction_file_that_held_only_the_section
    path = write(File.join(folder, "CLAUDE.md"), SECTION)
    removed(record(sections: [section_for(path)]))

    refute_path_exists path
  end

  def test_leaves_a_settings_file_that_is_not_json
    write(settings_path, "not json")
    removed(record(hooks: [{ "event" => "Stop", "command" => PLASTIC }]))

    assert_equal "not json", File.read(settings_path)
  end

  def test_plans_no_change_to_a_settings_file_that_is_gone
    file = write(File.join(folder, "plastic", "VERSION"), "2.0.5")
    planned = Plastic::Installations::Removal.new(record(files: [file]), plastic_home: @plastic_home).planned

    assert_equal [["remove:", file], ["remove:", File.dirname(file)], ["remove:", Plastic::Installations.path(@plastic_home, "claude-code")]], planned
  end

  def test_keeps_a_hook_group_that_holds_no_hook_list
    write(settings_path, JSON.generate("hooks" => { "Stop" => [{ "matcher" => "x" }, hook(PLASTIC)] }))
    removed(record(hooks: [{ "event" => "Stop", "command" => PLASTIC }]))

    assert_equal({ "Stop" => [{ "matcher" => "x" }] }, settings["hooks"])
  end
end
