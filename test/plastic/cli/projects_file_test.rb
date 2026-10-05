# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/projects_file"

class CLIProjectsFileTest < Plastic::TestCase
  def path = File.join(@plastic_home, "projects.yml")

  def file = Plastic::CLI::ProjectsFile.new(path)

  def test_a_missing_file_is_made_with_the_project
    file.add("blog", "/tmp/blog")

    assert_equal "projects:\n  blog:\n    path: /tmp/blog\n", File.read(path)
  end

  def test_a_file_with_other_keys_and_no_projects_gets_the_projects_key_after_them
    File.write(path, "other: 1")
    file.add("blog", "/tmp/blog")

    assert_equal "other: 1\nprojects:\n  blog:\n    path: /tmp/blog\n", File.read(path)
  end

  def test_a_file_that_ends_in_a_line_break_needs_no_extra_one
    File.write(path, "other: 1\n")
    file.add("blog", "/tmp/blog")

    assert_equal "other: 1\nprojects:\n  blog:\n    path: /tmp/blog\n", File.read(path)
  end

  def test_an_empty_projects_map_is_opened_for_the_project
    File.write(path, "projects: {}\n")
    file.add("blog", "/tmp/blog")

    assert_equal "projects:\n  blog:\n    path: /tmp/blog\n", File.read(path)
  end

  def test_a_new_project_goes_under_the_projects_key_beside_the_others
    File.write(path, "# mine\nprojects:\n  api:\n    path: /tmp/api\n")
    file.add("blog", "/tmp/blog")

    assert_equal "# mine\nprojects:\n  blog:\n    path: /tmp/blog\n  api:\n    path: /tmp/api\n", File.read(path)
  end

  def test_two_paths_of_one_folder_are_the_same_folder
    folder = Dir.mktmpdir

    assert Plastic::CLI::ProjectsFile.same_folder?(folder, File.join(folder, "."))
  end

  def test_a_path_that_is_gone_is_not_the_same_folder
    refute Plastic::CLI::ProjectsFile.same_folder?(File.join(@plastic_home, "gone"), @plastic_home)
  end
end
