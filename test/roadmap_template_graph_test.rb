# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/roadmap_graph"

# The roadmap template teaches "## Graph" (intent 337, n7) so a new roadmap
# is never born graphless, and the roadmap skill documents the three
# roadmap-graph verbs. Matrix rows from actions/ACTION_1.md S8/n7 (the
# template/skill/CHANGELOG half), plus 7.10/7.11 (existing tests that must
# stay green, asserted here only as a pointer - their own files own the
# assertions).
class RoadmapTemplateGraphTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  TEMPLATE_PATH = File.join(REPO, "templates", "roadmap.md")

  def template
    File.read(TEMPLATE_PATH)
  end

  # --- 7.5: the template carries a "## Graph" section --------------------------

  def test_template_carries_a_graph_section
    assert_match(/^## Graph$/, template)
  end

  # --- 7.6: the template's example edges produce no parse error ----------------

  def test_template_example_edges_produce_no_parse_error
    graph_section = template[/^## Graph$\n(.*?)(?=^## |\z)/m, 1]
    refute_nil graph_section
    stripped = GraphFile.strip_fenced_blocks(graph_section)
    parsed = GraphEdges.parse(stripped)
    assert_empty parsed[:errors]
  end

  # --- 7.7: the template parses through RoadmapGraph with no errors -----------

  def test_template_parses_through_the_roadmap_graph_model_with_no_errors
    Dir.mktmpdir("roadmap-template-parse") do |dir|
      path = File.join(dir, "roadmap.md")
      FileUtils.cp(TEMPLATE_PATH, path)
      result = RoadmapGraph.analyze(path)
      assert result[:has_graph], "template must carry a real ## Graph section: #{result[:reason]}"
      assert_nil result[:cycle]
      assert_empty result[:errors]
    end
  end

  # --- 7.8: CHANGELOG Unreleased names the roadmap graph -----------------------

  def test_changelog_unreleased_names_the_roadmap_graph
    changelog = File.read(File.join(REPO, "CHANGELOG.md"))
    unreleased = changelog[/^## Unreleased$\n(.*?)(?=^## |\z)/m, 1]
    refute_nil unreleased
    assert_match(/337 \(G4/, unreleased)
  end

  # --- 7.9: the roadmap skill documents the three verbs -------------------------

  def test_roadmap_skill_documents_the_three_verbs
    skill = File.read(File.join(REPO, "skills", "roadmap", "SKILL.md"))
    assert_match(/roadmap-graph check/, skill)
    assert_match(/roadmap-graph render/, skill)
    assert_match(/roadmap-graph migrate/, skill)
  end
end
