# frozen_string_literal: true

require_relative "../support/kernel"

class ScopeTest < Minitest::Test
  def setup
    @home = File.realpath(Dir.mktmpdir("plastic-scope"))
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "plastic"))
  end

  def teardown = FileUtils.remove_entry(@home)

  def scope(slug: nil, directory: @home, env: {"PLASTIC_HOME" => @plastic_home})
    Plastic::CLI::Scope.new(env:, home: @home, slug:, directory:)
  end

  def projects(text) = File.write(File.join(@plastic_home, "projects.yml"), text)

  def test_the_home_comes_from_the_environment
    assert_equal @plastic_home, scope.plastic_home
  end

  def test_the_home_falls_back_to_the_home_directory
    assert_equal File.join(@home, ".plastic"), scope(env: {}).plastic_home
  end

  def test_a_named_project_wins
    assert_equal "plastic", scope(slug: "plastic").slug
  end

  def test_an_unknown_project_names_the_known_ones
    error = assert_raises(Plastic::CLI::Scope::UnknownProject) { scope(slug: "nope").slug }

    assert_equal "no project named \"nope\"; this machine has global, plastic", error.message
  end

  def test_no_project_and_no_directory_match_is_global
    assert_equal "global", scope.slug
  end

  def test_the_directory_names_its_project
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(File.join(repo, "lib"))
    projects("plastic:\n  path: #{repo}\n")

    assert_equal "plastic", scope(directory: File.join(repo, "lib")).slug
    assert_equal "plastic", scope(directory: repo).slug
  end

  def test_the_inner_repository_wins
    outer = File.join(@home, "outer")
    inner = File.join(outer, "inner")
    FileUtils.mkdir_p(inner)
    projects("outer:\n  path: #{outer}\ninner:\n  path: #{inner}\n")

    assert_equal "inner", scope(directory: inner).slug
  end

  def test_a_sibling_with_a_shared_prefix_is_not_inside
    repo = File.join(@home, "app")
    FileUtils.mkdir_p([repo, "#{repo}2"])
    projects("app:\n  path: #{repo}\n")

    assert_equal "global", scope(directory: "#{repo}2").slug
  end

  def test_a_directory_that_does_not_exist_yet_still_resolves
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(repo)
    projects("plastic:\n  path: #{repo}\n")

    assert_equal "plastic", scope(directory: File.join(repo, "not", "yet")).slug
  end

  def test_a_project_with_no_path_matches_nothing
    projects("plastic: true\n")

    assert_equal({"plastic" => ""}, scope.projects)
    assert_equal "global", scope.slug
  end

  def test_no_projects_file_is_no_projects
    assert_empty scope.projects
  end

  def test_a_projects_file_that_is_not_a_map_stops_the_call
    projects("- plastic\n")
    error = assert_raises(Plastic::CLI::Scope::BrokenProjects) { scope.projects }

    assert_includes error.message, "does not hold a map of projects"
  end

  def test_a_projects_file_that_does_not_parse_stops_the_call
    projects("plastic: [\n")
    error = assert_raises(Plastic::CLI::Scope::BrokenProjects) { scope.projects }

    assert_includes error.message, "does not parse"
  end

  def test_the_root_is_the_store_directory
    assert_equal File.join(@plastic_home, "stores", "plastic"), scope(slug: "plastic").root
  end

  def test_the_known_slugs_are_the_store_directories_and_global
    File.write(File.join(@plastic_home, "stores", "a-file"), "")

    assert_equal %w[global plastic], scope.known_slugs
  end
end
