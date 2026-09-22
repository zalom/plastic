# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../bin/lib/context_budget"

# The standing surface (intent 363, plan step 7): every byte a session carries
# before it does any work. bin/plastic-bench is the one script that measures it,
# the agent catalog included, and the ceiling is the measured number, never a
# guess. It moves down as each skill family is removed, and never up.
class ContextBudgetAgentsTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @dir = Dir.mktmpdir("plastic-standing-surface")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def fixture_repo(agents)
    FileUtils.mkdir_p(File.join(@dir, "agents"))
    agents.each do |name, description|
      File.write(File.join(@dir, "agents", "#{name}.md"),
        "---\nname: #{name}\ndescription: #{description}\nmodel: opus\n---\n\nBody.\n")
    end
    @dir
  end

  def test_agent_paths_are_sorted
    repo = fixture_repo("zulu" => "last", "alpha" => "first")

    assert_equal %w[alpha.md zulu.md],
      ContextBudget.agent_paths(repo: repo).map { |path| File.basename(path) }
  end

  def test_agent_paths_are_empty_when_the_repository_has_no_agents
    assert_empty ContextBudget.agent_paths(repo: @dir)
  end

  def test_the_agent_catalog_counts_the_name_and_the_description_only
    repo = fixture_repo("alpha" => "twelve chars")

    assert_equal "alpha".bytesize + "twelve chars".bytesize,
      ContextBudget.agent_catalog_bytes(repo: repo)
  end

  def test_the_agent_catalog_sums_every_agent
    repo = fixture_repo("alpha" => "one", "beta" => "two")

    assert_equal "alphaone".bytesize + "betatwo".bytesize,
      ContextBudget.agent_catalog_bytes(repo: repo)
  end

  def test_the_agent_catalog_of_this_repository_is_measured_not_guessed
    assert_operator ContextBudget.agent_catalog_bytes(repo: REPO), :>, 0
  end

  def test_the_bench_reports_an_agent_catalog_row
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_equal ContextBudget.agent_catalog_bytes(repo: REPO), report.row(:agent_catalog).bytes
  end

  def test_the_agent_catalog_row_says_how_many_agents_it_counted
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_includes report.row(:agent_catalog).label,
      "#{ContextBudget.agent_paths(repo: REPO).length} name + description values"
  end

  def test_the_standing_row_is_the_sum_of_the_four_surfaces
    report = ContextBudget.run(repo: REPO, repeat: 1)
    parts = %i[core boot skill_catalog agent_catalog].sum { |key| report.row(key).bytes }

    assert_equal parts, report.row(:standing).bytes
  end

  # Intent 372: each family's skill deletions free their name + description bytes
  # from the skill catalog, measured by bin/plastic-bench. The ceiling moves down
  # by exactly that, never a round number. Family 1 (install, uninstall, update,
  # rollback) freed 1,332 bytes; family 2 (the five intent skills) freed 2,230;
  # family 4 (doctor, feedback, tutorial, conventions) freed 1,074; family 3
  # (project-creating, roadmap, dashboard) freed 1,073; family 5 (auto, direct,
  # agent-advisor, releasing) freed 1,503.
  # Intent 381 retired a deprecation notice whose removal had already shipped,
  # which freed 180 bytes of the boot injection.
  def test_the_standing_ceiling_reflects_every_family_so_far
    assert_equal 11_000 - 1_332 - 2_230 - 1_074 - 1_073 - 1_503 - 180, ContextBudget::CEILINGS[:standing]
  end

  def test_the_standing_row_carries_the_ceiling
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_equal ContextBudget::CEILINGS[:standing], report.row(:standing).ceiling
  end

  def test_the_standing_surface_holds_under_its_ceiling
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_operator report.row(:standing).bytes, :<=, ContextBudget::CEILINGS[:standing]
  end

  def test_the_ceiling_is_the_measured_number_rather_than_a_guess
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_operator report.row(:standing).headroom, :<=, 250,
      "the standing ceiling carries #{report.row(:standing).headroom} bytes of " \
      "headroom; it is set to the measured number, not to a round one"
  end

  def test_the_bench_passes_on_this_repository
    assert_predicate ContextBudget.run(repo: REPO, repeat: 1), :ok?
  end

  def test_a_standing_surface_over_the_ceiling_fails_the_bench
    over = File.join(@dir, "oversized.md")
    File.write(over, "x" * (ContextBudget::CEILINGS[:standing] + 1))
    report = ContextBudget.run(repo: REPO, repeat: 1, core_file: over)

    refute_predicate report, :ok?
  end

  def test_a_standing_surface_over_the_ceiling_names_the_standing_row
    over = File.join(@dir, "oversized.md")
    File.write(over, "x" * (ContextBudget::CEILINGS[:standing] + 1))
    report = ContextBudget.run(repo: REPO, repeat: 1, core_file: over)

    assert_includes report.failures.join(" "), "standing"
  end

  def test_the_rendered_table_carries_the_standing_row
    report = ContextBudget.run(repo: REPO, repeat: 1)

    assert_includes report.to_table, "standing surface"
  end
end
