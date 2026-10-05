# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# The shipped template and both tutorial tracks speak the runner vocabulary:
# the direct, thinking and auto modes, graph.md, plastic next and an End station.
class PostCutVocabularyTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def read(rel) = File.read(File.join(REPO, rel))

  def test_the_codex_template_names_the_three_modes
    body = codex_template

    %w[direct thinking auto].each { |mode| assert_match(/\b#{mode}\b/i, body) }
  end

  def test_the_codex_template_points_at_the_delivery_loop
    assert_match(/`plastic next`/, codex_template)
  end

  def test_both_tutorial_tracks_name_graph_md
    %w[track-1-guided track-2-auto].each { |track| assert_includes read("docs/help/#{track}.md"), "graph.md" }
  end

  def test_tutorial_track_1_walks_the_delivery_loop_to_an_end_station
    track = read("docs/help/track-1-guided.md")

    assert_match(/`plastic next`/, track)
    assert_match(/###\s*\d+\.\s*End\b/, track)
  end

  private

  def codex_template
    read("scripts/lib/installer_core.rb")[/CODEX_AGENTS_MD_BODY = <<~MD\.freeze\n(.*?)\n\s*MD\n/m, 1].to_s
  end
end
