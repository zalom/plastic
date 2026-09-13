# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# NamingRuleTest (intent 337a, node n5, D13/D14 amended): a thing is named
# after the concept family it lives under. PLASTIC.md carries no copy (the
# per-boot budget and the doctrine-305 gate word refuse it there); the
# knowledge-graph conventions chapter carries the paragraph verbatim, and the
# enforcer and executor agent files each carry one sentence that agrees with
# the chapter, without letting either agent file drift out of its current
# section shape.
class NamingRuleTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
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

  def test_naming_paragraph_names_the_three_families
    raw = section_body(File.read(KNOWLEDGE_GRAPH_MD), "Naming")
    refute_nil raw, "knowledge-graph.md has no '## Naming' section body"
    paragraph = raw.gsub(/\s+/, " ")

    assert_match(/graph engineering/, paragraph)
    assert_match(/node, edge, ready set, critical path/, paragraph)
    assert_match(/Plastic concepts coined on top of it/, paragraph)
    assert_match(/intent, ledger, packet, lease, gate, runner/, paragraph)
    assert_match(/software and AI engineering/, paragraph)
    assert_match(/review, fix, test, verify, dispatch, executor, reviewer/, paragraph)
  end

  def test_naming_paragraph_states_refusal_and_the_design_finding_route
    raw = section_body(File.read(KNOWLEDGE_GRAPH_MD), "Naming")
    refute_nil raw, "knowledge-graph.md has no '## Naming' section body"
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

  def test_the_sentences_agree_with_the_chapter
    chapter_paragraph = section_body(File.read(KNOWLEDGE_GRAPH_MD), "Naming").gsub(/\s+/, " ")
    refute_nil chapter_paragraph, "knowledge-graph.md has no '## Naming' section body"

    enforcer_body = File.read(ENFORCER_MD).gsub(/\s+/, " ")
    executor_raw = section_body(File.read(EXECUTOR_MD), "Constraints")
    refute_nil executor_raw, "plastic-executor.md has no '## Constraints' section body"
    executor_body = executor_raw.gsub(/\s+/, " ")

    [["enforcer", enforcer_body], ["executor", executor_body]].each do |name, body|
      assert_match(/graph engineering/, body, "#{name} sentence drops graph engineering")
      assert_match(/Plastic concepts coined on top of it/, body,
        "#{name} sentence drops the Plastic-concepts family")
      assert_match(/software and AI engineering/, body,
        "#{name} sentence drops the software and AI engineering family")

      names_refusal = body.match?(/is refused/)
      names_design_finding_route = body.match?(/design finding to raise, not a word to coin/)
      assert names_refusal || names_design_finding_route,
        "#{name} sentence states neither the refusal nor the design-finding route the chapter states"
    end

    assert_match(/graph engineering/, chapter_paragraph)
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
