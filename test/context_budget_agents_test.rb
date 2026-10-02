# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "tempfile"
require_relative "../bin/lib/context_budget"

# The standing surface (intent 363, plan step 7): every byte Plastic puts into a
# session before it does any work. bin/plastic-bench is the one script that
# measures it, the agent catalog included. The ceiling is the owner's cap of
# 2026-10-01 on what Plastic alone introduces, 5,000 bytes.
class ContextBudgetAgentsTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  # A plain `ContextBudget.run(repo: REPO, repeat: 1)` installs a real fixture
  # home and runs the session-start hook against it; nothing in this file
  # mutates REPO, so every test that asks for that one measurement shares it,
  # the way a Rails test suite boots its fixtures once per file.
  def self.report
    @report ||= ContextBudget.run(repo: REPO, repeat: 1)
  end

  def report = self.class.report

  # The two over-the-ceiling tests ask the same question (does a core file
  # past the cap fail the bench) of the same oversized content, so they share
  # one real measurement too, in a tmp file outside the per-test @dir.
  def self.over_ceiling_report
    @over_ceiling_report ||= begin
      oversized = Tempfile.create(["oversized-core", ".md"])
      oversized.write("x" * (ContextBudget::CEILINGS[:standing] + 1))
      oversized.close
      ContextBudget.run(repo: REPO, repeat: 1, core_file: oversized.path)
    end
  end

  def over_ceiling_report = self.class.over_ceiling_report

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
    assert_equal ContextBudget.agent_catalog_bytes(repo: REPO), report.row(:agent_catalog).bytes
  end

  def test_the_agent_catalog_row_says_how_many_agents_it_counted
    assert_includes report.row(:agent_catalog).label,
      "#{ContextBudget.agent_paths(repo: REPO).length} name + description values"
  end

  def test_the_standing_row_is_the_sum_of_the_four_surfaces
    parts = %i[core boot skill_catalog agent_catalog].sum { |key| report.row(key).bytes }

    assert_equal parts, report.row(:standing).bytes
  end

  # The owner ruled on 2026-10-01 that a cap sits only on what Plastic introduces,
  # never on the whole context, and set it at 5,000 bytes. It replaces the intent
  # 363 ratchet that followed each skill family's deletion down to 3,608.
  def test_the_standing_ceiling_is_the_owners_cap
    assert_equal 5_000, ContextBudget::CEILINGS[:standing]
  end

  def test_the_standing_row_carries_the_ceiling
    assert_equal ContextBudget::CEILINGS[:standing], report.row(:standing).ceiling
  end

  def test_the_standing_surface_holds_under_its_ceiling
    assert_operator report.row(:standing).bytes, :<=, ContextBudget::CEILINGS[:standing]
  end

  def test_the_standing_surface_leaves_room_for_rulings_in_the_core_block
    assert_operator report.row(:standing).headroom, :>=, 500,
      "the standing surface leaves #{report.row(:standing).headroom} bytes under the cap; " \
      "a ruling of a few lines in PLASTIC.md must fit without trimming"
  end

  def test_the_bench_passes_on_this_repository
    assert_predicate report, :ok?
  end

  def test_a_standing_surface_over_the_ceiling_fails_the_bench
    refute_predicate over_ceiling_report, :ok?
  end

  def test_a_standing_surface_over_the_ceiling_names_the_standing_row
    assert_includes over_ceiling_report.failures.join(" "), "standing"
  end

  def test_the_rendered_table_carries_the_standing_row
    assert_includes report.to_table, "standing surface"
  end
end
