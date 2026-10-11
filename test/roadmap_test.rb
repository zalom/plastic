# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Hermetic structural tests for the roadmap feature: they assert the roadmaps
# chapter (docs/help/roadmaps.md) states the contract invariants. Reads only
# in-repo files.
class RoadmapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ROADMAPS_CHAPTER = File.join(ROOT, "docs", "help", "roadmaps.md")

  # --- roadmap location ---

  def test_docs_do_not_place_roadmaps_under_store
    body = File.read(ROADMAPS_CHAPTER)

    refute_match(%r{store/roadmaps}, body, "#{ROADMAPS_CHAPTER} must not place roadmaps/ under store/")
    refute_match(/store[- ]root/i, body, "#{ROADMAPS_CHAPTER} must not describe roadmaps/ location as store-root")
  end

  def test_docs_state_the_roadmap_is_rows_printed_to_a_file
    body = File.read(ROADMAPS_CHAPTER)

    assert_match(/set of rows in the store's databases/, body, "#{ROADMAPS_CHAPTER} must state the roadmap lives in rows")
  end

  # --- roadmaps chapter contract ---

  def test_plastic_md_states_file_location
    body = File.read(ROADMAPS_CHAPTER)

    assert_includes body, "roadmaps/{slug}.md", "must name the roadmaps/{slug}.md location"
  end

  def test_plastic_md_states_the_four_sections
    body = File.read(ROADMAPS_CHAPTER)

    ["## Goal", "## Batch N", "## Graph", "## Log"].each do |heading|
      assert_includes body, heading, "must name section #{heading}"
    end
  end

  def test_plastic_md_states_wave_parallel_safety
    body = File.read(ROADMAPS_CHAPTER)

    assert_match(/parallel-safe/, body, "must state wave parallel-safety semantics")
  end

  def test_plastic_md_states_goal_as_prose_rule
    body = File.read(ROADMAPS_CHAPTER)

    assert_match(/checkable prose condition/, body, "must state the goal-as-prose rule")
  end

  def test_plastic_md_states_each_derived_item_state
    body = File.read(ROADMAPS_CHAPTER)

    ["`done`", "`dropped`", "`in flight`", "`blocked`", "`ready`"].each { |state| assert_includes body, state }
  end

  def test_plastic_md_states_purpose_line_verbatim
    body = File.read(ROADMAPS_CHAPTER)

    assert_includes body,
      "planned parallel delivery of intents in a coherent and organized way",
      "must state the verbatim purpose line"
  end

  def test_plastic_md_states_loop_relationship
    body = File.read(ROADMAPS_CHAPTER)

    assert_match(/planning half/i, body, "must state roadmap = planning half, loop = runtime")
  end

  def test_plastic_md_states_checkbox_and_em_to_cto_log_format
    body = File.read(ROADMAPS_CHAPTER)

    assert_match(/checkbox/i, body, "must mention the checkbox wave-entry rendering")
    assert_match(/outcome\.md/, body, "must mention linking log lines to outcome.md")
  end
end
