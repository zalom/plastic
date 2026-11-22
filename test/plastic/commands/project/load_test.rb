# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/project/load"
require_relative "../../../test_helpers/schema_versions"
require_relative "../../../../lib/plastic/graph/evidence/writer"

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

    result = load("blog")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal ["#{File.join(@plastic_home, "stores", "blog")} (missing)"], values(result, "store:")
    assert_empty values(result, "in play:")
  end

  def test_the_global_store_has_no_repository
    assert_includes lines(load("global")), "repo: none registered"
  end

  def test_a_project_with_a_repository_gets_an_architecture_line_for_the_agent_to_judge
    register("blog")
    work("blog")

    assert_equal ["when the repository holds code, check its architecture map with an architecture mapping tool such as Enola"], values(load("blog"), "architecture:")
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

  def test_the_then_line_names_the_kind_of_tool_that_checks_the_architecture_map
    assert_includes two_projects.find { |line| line.start_with?("then: ") }, "with an architecture mapping tool such as Enola"
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

# A store or a repository that cannot be read, and names that hold no project.
class ProjectLoadEdgeTest < Plastic::TestCase
  include ProjectLoadHelper
  include SchemaVersions

  def test_a_repository_that_is_gone_is_marked_missing_and_gets_no_read_or_architecture_line
    register("blog")
    work("blog")
    FileUtils.rm_rf(@repos.fetch("blog"))

    result = load("blog")

    assert_equal ["#{@repos.fetch("blog")} (missing)"], values(result, "repo:")
    assert_empty values(result, "read:") + values(result, "architecture:")
  end

  def test_an_empty_store_folder_is_named_and_left_empty
    register("blog")
    store = File.join(@plastic_home, "stores", "blog")
    FileUtils.mkdir_p(store)

    assert_equal ["#{store} (holds no database files)"], values(load("blog"), "store:")
    assert_empty Dir.children(store)
  end

  def test_a_store_out_of_step_is_named_and_the_next_project_still_loads
    register("blog", "shop")
    %w[blog shop].each { |slug| work(slug) }
    record_unknown_version(File.join(@plastic_home, "stores", "blog", "knowledge_graph.db"))

    result = load("blog", "shop")

    assert_equal [0, %w[blog shop]], [result.code, values(result, "project:")]
    assert_equal "#{File.join(@plastic_home, "stores", "blog")} (out of step with this code; run plastic update)", values(result, "store:").first
  end

  def test_a_project_registered_with_no_path_has_no_repository
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  blog:\n")
    work("blog")

    result = load("blog")

    assert_equal ["none registered"], values(result, "repo:")
    assert_empty values(result, "read:")
  end

  def test_names_that_hold_no_project_exit_2
    register("blog")

    result = load(",")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "name at least one project"
  end

  def test_deliveries_closed_in_different_zones_are_ordered_by_the_moment
    register("blog")
    later = store_intent("blog", "Late in New York", status: "done", closed_at: "2026-11-20T23:30:00-05:00")
    earlier = store_intent("blog", "Early in UTC", status: "done", closed_at: "2026-11-21T02:00:00Z")

    assert_equal [later.intent_id, earlier.intent_id], values(load("blog"), "delivered:").map { |line| line.split[1] }
  end
end

# The passages of the retrieval graph that a project load gives for the work in play.
class ProjectLoadRetrievalTest < Plastic::TestCase
  include ProjectLoadHelper

  def test_an_intent_in_play_gets_the_best_passages_of_the_other_intents_for_its_title
    register("blog")
    started = store_intent("blog", "Write the about page", status: "in_progress")
    index("blog", "7", "spec.md", "the about page uses a two column grid")
    index("blog", "8", "notes.md", "unrelated words about deployment")

    assert_equal ["for #{started.intent_id}: 7/spec.md - the about page uses a two column grid"], values(load("blog"), "context:")
  end

  def test_the_passages_of_the_intent_in_play_itself_are_not_its_context
    register("blog")
    started = store_intent("blog", "Write the about page", status: "in_progress")
    index("blog", started.intent_id, "spec.md", "the about page is the goal")

    assert_empty values(load("blog"), "context:")
  end

  def test_each_intent_in_play_gets_at_most_two_passages
    register("blog")
    store_intent("blog", "Write the about page", status: "in_progress")
    %w[1 2 3].each { |id| index("blog", id, "spec.md", "the about page, version #{id}") }

    assert_equal 2, values(load("blog"), "context:").size
  end

  def test_a_passage_is_cut_to_a_bounded_length_on_one_line
    register("blog")
    store_intent("blog", "Write the about page", status: "in_progress")
    index("blog", "7", "spec.md", "the about page\n#{"long " * 200}")

    row = values(load("blog"), "context:").first

    assert_operator row.length, :<=, 260
    refute_includes row, "\n"
  end

  def test_a_project_with_no_work_in_play_prints_no_context
    register("blog")
    store_intent("blog", "Idea")
    index("blog", "7", "spec.md", "idea")

    assert_empty values(load("blog"), "context:")
  end

  private

  def index(slug, intent_id, path, body)
    graphs = Plastic::Graph.create(home: @plastic_home, store: slug)
    origin = Plastic::Graph::Origin.new(@plastic_home).id
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK).write(intent_id, path, body)
    graphs.retrieval.repair
  end
end
