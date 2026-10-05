# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/project_new"
require_relative "../../../scripts/lib/plastic/commands/intent_new"

class ProjectNewTest < Plastic::TestCase
  def make(*argv) = plastic("project", "new", *argv, table: Plastic::CLI::TABLE)

  def projects_file = File.join(@plastic_home, "projects.yml")

  def checkout = (@checkout ||= Dir.mktmpdir)

  def test_a_fresh_name_registers_and_leaves_the_store_ready_for_intent_new
    result = make("blog", checkout)

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic intent new TITLE --project blog"
    assert_equal 0, plastic("intent", "new", "Alpha", "--project", "blog", table: Plastic::CLI::TABLE).code
  end

  def test_a_name_that_is_not_lowercase_letters_digits_and_dashes_is_a_usage_error
    assert_equal 2, make("Bad_Name", checkout).code
  end

  def test_global_is_refused
    result = make("global", checkout)

    assert_equal 3, result.code
    assert_match(/global/, result.err)
  end

  def test_a_path_that_is_not_a_directory_fails
    result = make("blog", File.join(checkout, "missing"))

    assert_equal 1, result.code
    assert_match(/not a directory/, result.err)
  end

  def test_a_name_registered_at_another_path_is_refused_and_the_file_kept
    make("blog", checkout)
    before = File.binread(projects_file)
    result = make("blog", Dir.mktmpdir)

    assert_equal 3, result.code
    assert_equal before, File.binread(projects_file)
  end

  def test_the_same_name_and_path_again_exits_zero_with_the_file_unchanged
    make("blog", checkout)
    before = File.binread(projects_file)

    assert_equal 0, make("blog", checkout).code
    assert_equal before, File.binread(projects_file)
  end

  def test_other_entries_and_keys_are_kept
    File.write(projects_file, "# mine\nprojects:\n  api:\n    path: /tmp/api\n    note: keep\nother: 1\n")
    make("blog", checkout)
    text = File.read(projects_file)

    assert_includes text, "  api:\n    path: /tmp/api\n    note: keep\n"
    assert_includes text, "other: 1"
    assert_includes text, "# mine"
    assert_equal({ "api" => "/tmp/api", "blog" => File.realpath(checkout) },
      YAML.load_file(projects_file)["projects"].transform_values { |entry| File.realpath(entry["path"]) rescue entry["path"] })
  end
end
