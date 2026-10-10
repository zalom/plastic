# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/project_list"

class ProjectListTest < Plastic::TestCase
  def list = plastic("project", "list", table: Plastic::CLI::TABLE)

  def register(slug, path, store: true)
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  #{slug}:\n    path: #{path}\n")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", slug)) if store
  end

  def test_with_none_registered_the_next_step_is_to_register_one
    result = list

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic project new SLUG PATH"
  end

  def test_a_registered_project_is_listed_with_its_path
    register("blog", "/tmp/blog")

    assert_includes list.out.lines.map { |line| line.squeeze(" ").strip }, "project blog: /tmp/blog"
  end

  def test_a_project_with_no_store_folder_says_so_on_its_line
    register("blog", "/tmp/blog", store: false)

    assert_includes list.out.lines.map { |line| line.squeeze(" ").strip }, "project blog: /tmp/blog (no store)"
  end
end
