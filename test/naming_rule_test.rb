# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# NamingRuleTest (intent 337a, node n5, D13/D14): a thing is named after the
# concept family it lives under. This test pins the owner's naming paragraph
# in PLASTIC.md and in the knowledge-graph conventions chapter, and pins one
# carrying sentence in each of the enforcer and executor agent files, without
# letting either agent file drift out of its current section shape.
class NamingRuleTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PLASTIC_MD = File.join(REPO, "PLASTIC.md")
  KNOWLEDGE_GRAPH_MD = File.join(REPO, "skills", "conventions", "references", "knowledge-graph.md")
  ENFORCER_MD = File.join(REPO, "agents", "plastic-enforcer.md")
  EXECUTOR_MD = File.join(REPO, "agents", "plastic-executor.md")

  def headings(body)
    body.lines.map(&:rstrip).select { |line| line.start_with?("## ") }
  end

  # Text of the section starting at "## <name>" up to (not including) the
  # next "## " heading, or EOF. Returns nil when the heading is absent.
  def section_body(body, name)
    lines = body.lines
    start_index = lines.index { |line| line.rstrip == "## #{name}" }
    return nil unless start_index

    rest = lines[(start_index + 1)..]
    end_offset = rest.index { |line| line.start_with?("## ") }
    section_lines = end_offset ? rest[0...end_offset] : rest
    section_lines.join.strip
  end

  def test_plastic_md_has_a_naming_section
    body = File.read(PLASTIC_MD)
    all_headings = headings(body)

    assert_includes all_headings, "## Naming", "PLASTIC.md is missing a '## Naming' section"

    house_style_index = all_headings.index("## House Style (self-check)")
    qmd_index = all_headings.index { |h| h.start_with?("## QMD, Enola") }
    naming_index = all_headings.index("## Naming")

    refute_nil house_style_index, "PLASTIC.md is missing '## House Style (self-check)'"
    refute_nil qmd_index, "PLASTIC.md is missing the '## QMD, Enola, and Serena' heading"
    assert_equal house_style_index + 1, naming_index,
      "'## Naming' must sit directly after '## House Style (self-check)'"
    assert_equal naming_index + 1, qmd_index,
      "'## Naming' must sit directly before '## QMD, Enola, and Serena'"
  end

  def test_naming_paragraph_names_the_three_families
    raw = section_body(File.read(PLASTIC_MD), "Naming")
    refute_nil raw, "PLASTIC.md has no '## Naming' section body"
    paragraph = raw.gsub(/\s+/, " ")

    assert_match(/graph engineering/, paragraph)
    assert_match(/node, edge, ready set, critical path/, paragraph)
    assert_match(/Plastic concepts coined on top of it/, paragraph)
    assert_match(/intent, ledger, packet, lease, gate, runner/, paragraph)
    assert_match(/software and AI engineering/, paragraph)
    assert_match(/review, fix, test, verify, dispatch, executor, reviewer/, paragraph)
  end

  def test_naming_paragraph_states_refusal_and_the_design_finding_route
    raw = section_body(File.read(PLASTIC_MD), "Naming")
    refute_nil raw, "PLASTIC.md has no '## Naming' section body"
    paragraph = raw.gsub(/\s+/, " ")

    assert_match(/A name from outside that stack is refused\./, paragraph)
    assert_match(/that is a design finding to raise, not a word to coin\./, paragraph)
  end

  def test_conventions_chapter_carries_the_rule
    body = File.read(KNOWLEDGE_GRAPH_MD)
    assert_includes headings(body), "## Naming",
      "knowledge-graph.md is missing a '## Naming' heading"

    paragraph = section_body(body, "Naming")
    refute_nil paragraph, "knowledge-graph.md has no '## Naming' section body"
    assert_match(/A thing is named after the concept family it lives under\./, paragraph)
  end

  def test_the_two_copies_agree
    normalize = ->(text) { text.gsub(/\s+/, " ").strip }

    plastic_paragraph = section_body(File.read(PLASTIC_MD), "Naming")
    conventions_paragraph = section_body(File.read(KNOWLEDGE_GRAPH_MD), "Naming")

    refute_nil plastic_paragraph, "PLASTIC.md has no '## Naming' section body"
    refute_nil conventions_paragraph, "knowledge-graph.md has no '## Naming' section body"

    assert_equal normalize.call(plastic_paragraph), normalize.call(conventions_paragraph),
      "the PLASTIC.md and knowledge-graph.md naming paragraphs must agree after whitespace normalization"
  end

  def test_enforcer_carries_the_naming_sentence
    body = File.read(ENFORCER_MD).gsub(/\s+/, " ")

    assert_match(/concept family it lives under/, body)
    assert_match(/graph engineering/, body)
    assert_match(/Plastic concepts coined on top of it/, body)
    assert_match(/software and AI engineering/, body)
    assert_match(/design finding to raise, not a word to coin/, body)
  end

  def test_executor_carries_the_naming_sentence
    body = File.read(EXECUTOR_MD)
    raw_constraints = section_body(body, "Constraints")
    refute_nil raw_constraints, "plastic-executor.md has no '## Constraints' section body"
    constraints = raw_constraints.gsub(/\s+/, " ")

    assert_match(/concept family/, constraints)
    assert_match(/graph engineering/, constraints)
    assert_match(/Plastic concepts coined on top of it/, constraints)
    assert_match(/software and AI engineering/, constraints)
  end

  def test_executor_contract_sections_are_unchanged
    executor_headings = headings(File.read(EXECUTOR_MD))
    assert_equal(
      ["## Your Responsibilities", "## How You Work", "## Completion Report", "## Constraints"],
      executor_headings
    )

    enforcer_headings = headings(File.read(ENFORCER_MD))
    assert_equal(
      ["## Your Responsibilities", "## How You Work", "## Human-facing reporting", "## Constraints"],
      enforcer_headings
    )
  end
end
