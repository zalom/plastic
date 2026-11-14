# frozen_string_literal: true

require_relative "../../support/removal_fixture"

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
