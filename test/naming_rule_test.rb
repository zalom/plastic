# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# A thing is named after the concept family it lives under. The knowledge-graph
# chapter carries the rule, and the planner and executor agent files each carry
# one sentence that agrees with it.
class NamingRuleTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  KNOWLEDGE_GRAPH_MD = File.join(REPO, "docs", "help", "knowledge-graph.md")
  PLANNER_MD = File.join(REPO, "agents", "plastic-planner.md")
  EXECUTOR_MD = File.join(REPO, "agents", "plastic-executor.md")

  def headings(body)
    body.lines.map(&:rstrip).select { |line| line.start_with?("## ") }
  end

  def section_body(body, name)
    lines = body.lines
    start_index = lines.index { |line| line.rstrip == "## #{name}" }
    return nil unless start_index

    rest = lines[(start_index + 1)..]
    end_offset = rest.index { |line| line.start_with?("## ") }
    section_lines = end_offset ? rest[0...end_offset] : rest
    section_lines.join.strip
  end

  def naming_paragraph = section_body(File.read(KNOWLEDGE_GRAPH_MD), "Naming").to_s.gsub(/\s+/, " ")

  def test_naming_paragraph_names_the_three_families
    families = ["graph engineering", "node, edge, ready set, critical path", "Plastic concepts coined on top of it",
      "intent, ledger, node input, lease, gate, runner", "software and AI engineering",
      "review, fix, test, verify, dispatch, executor, reviewer"]

    families.each { |family| assert_includes naming_paragraph, family }
  end

  def test_naming_paragraph_states_refusal_and_the_design_finding_route
    ["A name from outside that stack is refused.", "that is a design finding to raise, not a word to coin."]
      .each { |phrase| assert_includes naming_paragraph, phrase }
  end

  def test_conventions_chapter_carries_the_rule
    assert_includes naming_paragraph, "A thing is named after the concept family it lives under."
  end

  def test_planner_carries_the_naming_sentence
    body = File.read(PLANNER_MD).gsub(/\s+/, " ")
    phrases = ["concept family it lives under", "graph engineering", "Plastic concepts coined on top of it",
      "software and AI engineering", "design finding to raise, not a word to coin"]

    phrases.each { |phrase| assert_includes body, phrase }
  end

  def test_executor_carries_the_naming_sentence
    constraints = section_body(File.read(EXECUTOR_MD), "Constraints").to_s.gsub(/\s+/, " ")

    ["concept family", "graph engineering", "Plastic concepts coined on top of it", "software and AI engineering"]
      .each { |phrase| assert_includes constraints, phrase }
  end

  def test_executor_contract_sections_are_unchanged
    assert_equal ["## Your Responsibilities", "## How You Work", "## Completion Report", "## Constraints", "## Planning directive"],
      headings(File.read(EXECUTOR_MD))
  end

  def test_planner_contract_sections_match_the_executor
    assert_equal ["## Your Responsibilities", "## How You Work", "## Completion Report", "## Constraints", "## Planning directive"],
      headings(File.read(PLANNER_MD))
  end
end
