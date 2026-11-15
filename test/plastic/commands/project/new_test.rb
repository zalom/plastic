# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/project/new"
require_relative "../../../../lib/plastic/commands/intent/new"

class ProjectNewCaseTest < Plastic::TestCase
  def test_registering_a_project_prints_its_home_and_offers_the_first_intent
    assert_case line("project new blog #{@home}"), code: 0, out: ["project blog: #{@home}", "next: plastic intent new TITLE --project blog"]
  end

  def test_registering_the_same_project_again_prints_the_same_lines
    ran("project new blog #{@home}")

    assert_case line("project new blog #{@home}"), code: 0, out: ["project blog: #{@home}", "next: plastic intent new TITLE --project blog"]
  end

  def test_a_name_with_a_capital_or_an_underscore_exits_2_and_names_the_rule
    assert_case line("project new Bad_Name #{@home}"), code: 2, out: "", err: ["the name must be lowercase letters, digits and dashes"]
  end
end

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
    assert_equal ["other: 1", "# mine"], [text[/other: 1/], text[/# mine/]]
  end

  def test_the_new_project_is_listed_with_its_folder_beside_the_others
    File.write(projects_file, "projects:\n  api:\n    path: /tmp/api\n")
    make("blog", checkout)
    projects = YAML.load_file(projects_file)["projects"]

    assert_equal ["/tmp/api", File.realpath(checkout)], [projects["api"]["path"], File.realpath(projects["blog"]["path"])]
  end

  def rule_file(name) = File.join(checkout, name)

  def test_both_rule_files_absent_are_written_and_named
    result = make("blog", checkout)

    assert_equal "# blog\n\nRules for agents working on this repository.\n\n" \
                 "Plastic's instructions are in ~/.plastic/PLASTIC.md.\n", File.read(rule_file("AGENTS.md"))
    assert_equal "@AGENTS.md\n", File.read(rule_file("CLAUDE.md"))
    assert_includes result.out, "created  AGENTS.md and CLAUDE.md in #{checkout}"
  end

  def test_a_present_agents_file_is_left_byte_for_byte
    File.write(rule_file("AGENTS.md"), "mine\n")
    result = make("blog", checkout)

    assert_equal "mine\n", File.read(rule_file("AGENTS.md"))
    assert_includes result.out, "created  CLAUDE.md in #{checkout}"
  end

  def test_a_claude_file_without_the_import_is_left_byte_for_byte
    File.write(rule_file("CLAUDE.md"), "no import\n")
    make("blog", checkout)

    assert_equal "no import\n", File.read(rule_file("CLAUDE.md"))
  end

  def test_a_second_call_changes_no_file_and_names_none
    make("blog", checkout)
    before = %w[AGENTS.md CLAUDE.md].map { |name| File.binread(rule_file(name)) }
    result = make("blog", checkout)

    assert_equal before, %w[AGENTS.md CLAUDE.md].map { |name| File.binread(rule_file(name)) }
    refute_includes result.out, "created"
  end
end
