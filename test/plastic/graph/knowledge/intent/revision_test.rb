# frozen_string_literal: true

require_relative "../../../../test_helper"

class IntentRevisionTest < Plastic::TestCase
  KERNEL_PAGE = <<~MD
    ---
    id: "7"
    intent: "Old line"
    ---

    # 7 - Old line

    ## Intent

    Old line

    ## Context

    ## Outcome

    ## Insights
  MD

  LEGACY_PAGE = <<~MD
    ---
    id: "415"
    intent: "Old line"
    chain: []
    ---

    ## Intent
    Old line

    ## Context
    (why this intent exists)

    ### Decisions
    - D1 keep it

    ## Outcome
    (the result)
  MD

  NO_CONTEXT_PAGE = <<~MD
    ## Intent
    Old line

    ## Outcome
    (the result)
  MD

  def revise(body, line, why = nil) = Plastic::Graph::Knowledge::Intent::Revision.new(body, "7").revise(line, why)

  def test_a_new_line_replaces_the_heading_the_front_matter_and_the_intent_section
    assert_equal KERNEL_PAGE.gsub("Old line", "New line"), revise(KERNEL_PAGE, "New line")
  end

  def test_without_why_the_context_section_is_unchanged
    revised = revise(LEGACY_PAGE, "New line")

    assert_includes revised, "## Context\n(why this intent exists)\n\n### Decisions\n- D1 keep it\n"
  end

  def test_why_replaces_the_context_lead_and_keeps_its_subsections
    revised = revise(LEGACY_PAGE, "New line", "Because grilling moved it")

    assert_includes revised, "## Context\nBecause grilling moved it\n\n### Decisions\n- D1 keep it\n\n## Outcome\n(the result)\n"
    refute_includes revised, "(why this intent exists)"
  end

  def test_why_on_a_kernel_page_keeps_outcome_and_insights
    revised = revise(KERNEL_PAGE, "New line", "Because grilling moved it")

    assert_includes revised, "## Context\n\nBecause grilling moved it\n\n## Outcome\n\n## Insights\n"
  end

  def test_a_legacy_page_replaces_its_front_matter_and_intent_line
    revised = revise(LEGACY_PAGE, "New line")

    assert_includes revised, %(intent: "New line"\nchain: []\n)
    assert_includes revised, "## Intent\nNew line\n\n## Context"
    refute_includes revised, "# 7 - "
  end

  def test_why_on_a_page_without_context_adds_it_before_outcome
    revised = revise(NO_CONTEXT_PAGE, "New line", "Because grilling moved it")

    assert_equal "## Intent\nNew line\n\n## Context\n\nBecause grilling moved it\n\n## Outcome\n(the result)\n", revised
  end

  def test_the_front_matter_line_is_json_quoted
    revised = revise(KERNEL_PAGE, %(Say "hi": now))

    assert_includes revised, %(intent: "Say \\"hi\\": now"\n)
  end

  def test_the_why_reads_the_context_lead_as_one_line
    why = Plastic::Graph::Knowledge::Intent::Revision.new(LEGACY_PAGE, "415").why

    assert_equal "(why this intent exists)", why
  end
end
