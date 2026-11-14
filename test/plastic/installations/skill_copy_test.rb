# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/skill_copy"

class SkillCopyTest < Plastic::TestCase
  include PackageFixture

  def copy(root, **options) = Plastic::Installations::SkillCopy.new(root, @plastic_home).call(File.join(@home, "installed"), **options)

  def test_a_skill_folder_is_copied_whole_and_a_shared_fragment_lands_in_the_plastic_home
    root = package(skills: { "demo/refs/a.md" => "a\n", "_shared.md" => "shared\n", ".hidden/x.md" => "h\n" })

    assert_equal [File.join(@home, "installed", "plastic-demo", "refs", "a.md"), File.join(@plastic_home, "_shared.md")].sort, copy(root).sort
  end

  def test_an_excluded_skill_is_left_out
    root = package(skills: { "agent-advisor/a.md" => "a\n", "demo/b.md" => "b\n" })

    assert_equal [File.join(@home, "installed", "plastic-demo", "b.md")], copy(root, exclude: ["agent-advisor"])
  end

  def test_a_package_with_no_skills_folder_copies_nothing_and_makes_no_folder
    assert_equal [[], false], [copy(package), File.exist?(File.join(@home, "installed"))]
  end

  def test_a_loose_file_that_is_not_a_fragment_is_ignored
    root = package(skills: { "notes.txt" => "n\n" })

    assert_empty copy(root)
  end

  def test_the_fragments_name_the_files_a_prune_may_reach
    root = package(skills: { "_shared.md" => "s\n", "demo/a.md" => "a\n" })

    assert_equal [File.join(@plastic_home, "_shared.md")], Plastic::Installations::SkillCopy.new(root, @plastic_home).fragments
  end

  def test_a_package_with_no_skills_names_no_fragment
    assert_empty Plastic::Installations::SkillCopy.new(package, @plastic_home).fragments
  end
end
