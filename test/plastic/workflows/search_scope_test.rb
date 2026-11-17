# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/search_scope"

class WorkflowSearchScopeTest < Plastic::TestCase
  include ConfigHomes

  def sources(source_projects, env: {})
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "other"))
    context = call_context(harness: scoped_harness(slug: "global", env:), source_projects:)
    Plastic::Workflows::SearchScope.new(context).sources
  end

  def test_no_selection_searches_the_current_store
    assert_equal ["global"], sources([])
  end

  def test_named_projects_are_trimmed_deduplicated_and_sorted
    assert_equal %w[global other], sources([" other", "global", "other", ""])
  end

  def configure(value) = seed_config(@plastic_home, { "global" => { "search" => { "source_projects" => value } } }.to_yaml)

  def test_the_environment_variable_is_not_read
    assert_equal ["global"], sources([], env: { "PLASTIC_SOURCE_PROJECTS" => "other" })
  end

  def test_the_config_key_selects_projects_when_none_are_named
    configure("other")

    assert_equal ["other"], sources([])
  end

  def test_the_config_key_takes_a_comma_list
    configure("other,global")

    assert_equal %w[global other], sources([])
  end

  def test_named_projects_replace_the_config_key
    configure("other")

    assert_equal ["global"], sources(["global"])
  end

  def test_an_unknown_project_in_the_config_key_is_a_usage_error
    configure("missing")

    assert_equal "unknown source projects: missing", assert_raises(Plastic::CLI::Command::Usage) { sources([]) }.message
  end

  def test_an_unknown_project_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { sources(%w[missing]) }

    assert_equal "unknown source projects: missing", error.message
  end
end
