# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli/scope"

class CliScopeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-cli-scope")
    @fixture = CliFixture.new(@dir)
      .global_store(active: [["41", "Security first"]])
      .project("plastic", active: [["363", "The command line"]])
      .project("better-say", active: [])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def scope(slug: nil, directory: "/nowhere")
    Plastic::CLI::Scope.new(env: @fixture.env, home: @fixture.home, slug: slug, directory: directory)
  end

  def test_the_plastic_home_comes_from_the_injected_environment
    assert_equal @fixture.plastic_home, scope.plastic_home
  end

  def test_the_plastic_home_falls_back_to_the_injected_home_directory
    resolved = Plastic::CLI::Scope.new(env: {}, home: @fixture.home, slug: nil, directory: "/nowhere")

    assert_equal File.join(@fixture.home, ".plastic"), resolved.plastic_home
  end

  def test_a_named_project_resolves_to_its_store
    assert_equal "plastic", scope(slug: "plastic").slug
    assert_equal File.join(@fixture.plastic_home, "projects", "plastic", "store"), scope(slug: "plastic").store
  end

  def test_a_named_project_resolves_to_its_index_and_roadmaps
    resolved = scope(slug: "plastic")
    root = File.join(@fixture.plastic_home, "projects", "plastic")

    assert_equal File.join(root, "INDEX.md"), resolved.index_path
    assert_equal File.join(root, "roadmaps"), resolved.roadmaps_dir
  end

  def test_an_unknown_project_is_refused_with_the_known_slugs
    error = assert_raises(Plastic::CLI::Scope::UnknownProject) { scope(slug: "nope").slug }

    assert_includes error.message, "nope"
    assert_includes error.message, "better-say, global, plastic"
  end

  def test_with_no_slug_the_working_directory_picks_the_project
    inside = File.join(@fixture.home, "code", "plastic", "scripts")

    assert_equal "plastic", scope(directory: inside).slug
  end

  def test_the_longest_matching_repository_path_wins
    root = File.join(@fixture.home, "code")
    nested = Plastic::CLI::Scope.new(env: @fixture.env, home: @fixture.home, slug: nil,
                                     directory: File.join(root, "plastic"))

    assert_equal "plastic", nested.slug
  end

  def test_a_repository_path_that_is_only_a_string_prefix_does_not_match
    outside = File.join(@fixture.home, "code", "plastic-other")

    assert_equal "global", scope(directory: outside).slug
  end

  def test_a_directory_outside_every_project_falls_back_to_global
    assert_equal "global", scope(directory: "/nowhere").slug
  end

  def test_the_global_scope_points_at_the_plastic_home
    resolved = scope(directory: "/nowhere")

    assert_equal @fixture.plastic_home, resolved.root
    assert_equal File.join(@fixture.plastic_home, "store"), resolved.store
    assert_equal File.join(@fixture.plastic_home, "INDEX.md"), resolved.index_path
  end

  def test_stores_lists_every_store_with_global_first
    assert_equal %w[global better-say plastic], scope.stores.map { |s| s[:slug] }
  end

  def test_active_ids_reads_the_index_active_section
    assert_equal ["363"], scope(slug: "plastic").active_ids
  end

  def test_active_ids_answers_nothing_for_a_store_with_no_index
    @fixture.drop_index("plastic")

    assert_empty scope(slug: "plastic").active_ids
  end

  def test_active_titles_pair_the_id_with_its_line
    assert_equal [["41", "Security first"]], scope.active_entries
  end

  def test_the_intent_directory_is_found_by_id
    expected = @fixture.intent_dir("plastic", "363")

    assert_equal expected, scope(slug: "plastic").intent_dir("363")
  end

  def test_an_unknown_intent_id_has_no_directory
    assert_nil scope(slug: "plastic").intent_dir("999")
  end
end
