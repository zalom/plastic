# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/project/load"

# Calls and fixtures the project load tests share.
module ProjectLoadHelper
  def load(*args) = plastic("project", "load", *args, table: Plastic::CLI::TABLE)

  def lines(result) = result.out.lines(chomp: true).map { |line| line.squeeze(" ").strip }

  def values(result, label) = lines(result).filter_map { |line| line.delete_prefix("#{label} ") if line.start_with?("#{label} ") }

  def register(*slugs)
    @repos = slugs.to_h { |slug| [slug, File.join(@home, "repos", slug).tap { |path| FileUtils.mkdir_p(path) }] }
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n#{@repos.map { |slug, path| "  #{slug}:\n    path: #{path}\n" }.join}")
  end

  def work(slug) = Plastic::Graph.create(home: @plastic_home, store: slug).work

  def store_intent(slug, title, status: "open", closed_at: nil)
    intent = work(slug).write_intent(title:)
    database = Plastic::Graph.open(home: @plastic_home, store: slug).databases.fetch(:store)
    database.transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = :status, closed_at = :closed_at WHERE intent_id = :intent_id",
        status:, closed_at:, intent_id: intent.intent_id)
    end
    intent
  end
end

class ProjectLoadTest < Plastic::TestCase
  include ProjectLoadHelper

  def test_a_named_project_prints_its_store_and_its_repository_with_exit_0
    register("blog")
    work("blog")

    result = load("blog")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal ["project: blog", "store: #{File.join(@plastic_home, "stores", "blog")}", "repo: #{@repos.fetch("blog")}"], lines(result).first(3)
  end

  def test_the_agents_and_readme_files_that_exist_are_named_to_read
    register("blog")
    work("blog")
    File.write(File.join(@repos.fetch("blog"), "AGENTS.md"), "# Blog\n")

    assert_equal [File.join(@repos.fetch("blog"), "AGENTS.md")], values(load("blog"), "read:")
  end

  def test_the_intents_in_progress_are_listed_and_the_waiting_ones_counted
    register("blog")
    started = store_intent("blog", "Write the about page", status: "in_progress")
    2.times { |index| store_intent("blog", "Idea #{index}") }

    result = load("blog")

    assert_equal ["#{started.intent_id} Write the about page"], values(result, "in play:")
    assert_equal ["2 open intents; plastic status --project blog lists them"], values(result, "waiting:")
  end

  def test_the_last_three_delivered_intents_are_listed_newest_first_with_their_day
    register("blog")
    days = %w[2026-11-17 2026-11-18 2026-11-19 2026-11-20]
    delivered = days.map { |day| [day, store_intent("blog", "Post of #{day}", status: "done", closed_at: "#{day}T12:00:00Z")] }

    expected = delivered.last(3).reverse.map { |day, intent| "#{Plastic.local_day("#{day}T12:00:00Z")} #{intent.intent_id} Post of #{day}" }

    assert_equal expected, values(load("blog"), "delivered:")
  end

  def test_a_delivery_closed_on_a_date_only_shows_that_date
    register("blog")
    intent = store_intent("blog", "Old post", status: "done", closed_at: "2025-03-04")

    assert_equal ["2025-03-04 #{intent.intent_id} Old post"], values(load("blog"), "delivered:")
  end

  def test_a_project_with_no_store_folder_says_so_and_lists_no_work
    register("blog")
    FileUtils.rm_rf(@repos.fetch("blog"))

    result = load("blog")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal ["store: #{File.join(@plastic_home, "stores", "blog")} (missing)", "repo: #{@repos.fetch("blog")} (missing)"], lines(result)[1, 2]
    assert_empty values(result, "in play:")
  end

  def test_the_global_store_has_no_repository
    assert_includes lines(load("global")), "repo: none registered"
  end

  def test_a_project_with_a_repository_gets_an_architecture_line_for_the_agent_to_judge
    register("blog")
    work("blog")

    assert_equal ["when the repository holds code, check its architecture map with a tool such as Enola"], values(load("blog"), "architecture:")
  end

  def test_the_global_store_with_no_repository_gets_no_architecture_line
    assert_empty values(load("global"), "architecture:")
  end

  def test_each_project_names_the_search_that_reaches_the_rest_of_its_knowledge
    register("blog")
    work("blog")

    assert_equal ["plastic search TERMS --source-project blog"], values(load("blog"), "search:")
  end

  def test_several_projects_in_words_and_commas_each_print_a_digest
    register("blog", "shop", "wiki")
    %w[blog shop wiki].each { |slug| work(slug) }

    assert_equal %w[blog shop wiki], values(load("blog", "shop,wiki"), "project:")
  end
end

# The digest of several projects, the then line, and the refusals.
class ProjectLoadCallTest < Plastic::TestCase
  include ProjectLoadHelper

  def two_projects
    register("blog", "shop")
    %w[blog shop].each { |slug| work(slug) }
    lines(load("blog", "shop")).reject(&:empty?)
  end

  def test_one_then_line_follows_the_digests_of_every_project
    printed = two_projects

    assert_equal 1, printed.count { |line| line.start_with?("then: ") }
    assert_match(/\Athen: /, printed[-2])
  end

  def test_no_next_line_is_printed_because_the_next_work_waits_for_the_owner
    printed = two_projects

    refute printed.any? { |line| line.start_with?("next:") }
    assert_equal "because: the projects are loaded; the next work waits for the owner's ask", printed.last
  end

  def test_one_open_intent_is_counted_in_the_singular
    register("blog")
    store_intent("blog", "Idea")

    assert_equal ["1 open intent; plastic status --project blog lists them"], values(load("blog"), "waiting:")
  end

  def test_an_unregistered_name_exits_2_and_names_the_registered_projects
    register("blog")

    result = load("blog", "nope")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "no registered project named \"nope\"; the projects are blog"
  end

  def test_with_no_name_the_calls_own_store_is_loaded
    register("blog")
    work("blog")

    assert_equal ["blog"], values(load("--project", "blog"), "project:")
  end

  def test_names_together_with_project_exit_2
    register("blog")

    result = load("blog", "--project", "blog")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--project does not apply"
  end
end
