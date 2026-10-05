# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/discovery_scope"

class DiscoveryScopeTest < Plastic::TestCase
  def resolve(source_projects = [], env: {})
    Plastic::Workflows::DiscoveryScope.resolve(call_context(harness: scoped_harness(env:), source_projects:))
  end

  def store(slug) = FileUtils.mkdir_p(File.join(@plastic_home, "stores", slug))

  def test_no_source_named_selects_the_calling_store
    assert_equal ["global"], resolve
  end

  def test_the_named_sources_come_back_sorted_and_unique
    store("other")

    assert_equal %w[global other], resolve(["other", " global", "other"])
  end

  def test_the_sources_of_the_injected_environment_are_used_when_none_is_named
    store("other")

    assert_equal ["other"], resolve(env: { "PLASTIC_SOURCE_PROJECTS" => "other," })
  end

  def test_an_unknown_source_fails_the_call
    error = assert_raises(Plastic::CLI::Command::Failure) { resolve(%w[missing]) }

    assert_equal "unknown source projects: missing", error.message
  end

  def test_a_file_named_like_a_store_is_not_a_store
    File.write(File.join(store("x").first, "..", "loose"), "")

    assert_raises(Plastic::CLI::Command::Failure) { resolve(%w[loose]) }
  end
end
