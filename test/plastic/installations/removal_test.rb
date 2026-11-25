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

  def test_removes_the_status_line_plastic_set_when_it_replaced_none
    write(settings_path, JSON.generate("statusLine" => { "type" => "command", "command" => "plastic-statusline" }))
    removed(record(status_line: { "command" => "plastic-statusline", "replaced" => nil }))

    refute_path_exists settings_path
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

# What Installations::Removal names for each path it changed, and the folders it takes away.
class InstallationsRemovalRowsTest < Plastic::TestCase
  include RemovalFixture

  def test_deletes_the_record_and_names_each_path_it_removed
    file = write(File.join(folder, "plastic", "VERSION"), "2.0.5")
    paths = removed(record(files: [file]))

    assert_equal [nil, [["removed:", file], ["removed:", File.dirname(file)]]], [Plastic::Installations.read(@plastic_home, "claude-code"), paths]
  end

  def test_names_a_rewritten_settings_file_as_stripped
    write(settings_path, JSON.generate("model" => "opus", "hooks" => { "Stop" => [hook(PLASTIC)] }))

    assert_equal [["stripped:", settings_path]], removed(record(hooks: [{ "event" => "Stop", "command" => PLASTIC }]))
  end

  def test_names_a_settings_file_left_empty_as_removed
    write(settings_path, JSON.generate("hooks" => { "Stop" => [hook(PLASTIC)] }))

    assert_equal [["removed:", settings_path]], removed(record(hooks: [{ "event" => "Stop", "command" => PLASTIC }]))
  end

  def test_names_an_instruction_file_with_the_section_taken_out_as_stripped
    path = write(File.join(folder, "CLAUDE.md"), "# Mine\n\n#{SECTION}")

    assert_equal [["stripped:", path]], removed(record(sections: [section_for(path)]))
  end

  def test_removes_the_folder_that_the_removal_emptied
    file = write(File.join(folder, "skills", "plastic-x", "SKILL.md"), "x")
    rows = removed(record(files: [file], folders: [File.dirname(file)]))

    assert_includes rows, ["removed:", File.join(folder, "skills")]
    refute_path_exists File.join(folder, "skills")
  end

  def test_keeps_a_folder_that_was_empty_before_the_removal
    file = write(File.join(folder, "skills", "plastic-x", "SKILL.md"), "x")
    FileUtils.mkdir_p(File.join(folder, "commands"))
    removed(record(files: [file], folders: [File.dirname(file)]))

    assert_path_exists File.join(folder, "commands")
  end

  def test_removes_the_empty_agents_skills_and_hooks_folders_an_install_made
    %w[agents skills hooks].each { |name| FileUtils.mkdir_p(File.join(folder, name)) }
    removed(record)

    assert_empty %w[agents skills hooks].select { |name| File.exist?(File.join(folder, name)) }
  end

  def test_keeps_other_empty_folders_when_it_removes_the_install_folders
    FileUtils.mkdir_p(File.join(folder, "commands"))
    removed(record)

    assert_path_exists File.join(folder, "commands")
  end

  def test_keeps_a_folder_that_still_holds_a_file_of_the_person_after_the_removal
    file = write(File.join(folder, "agents", "plastic-x.md"), "x")
    write(File.join(folder, "agents", "mine.md"), "mine")
    removed(record(files: [file]))

    assert_path_exists File.join(folder, "agents", "mine.md")
  end
end
