# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# A dispatched agent commits its code and reports; the main session records.
# This contract test pins that wording in the executor and planner agent
# bodies, and the tick-lag warning in docs/internals.md.
class NodeReportContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXECUTOR = File.join(ROOT, "agents/plastic-executor.md")
  PLANNER = File.join(ROOT, "agents/plastic-planner.md")
  INTERNALS = File.join(ROOT, "docs/internals.md")

  def squeeze(text) = text.gsub(/\s+/, " ")

  def section(body, heading)
    raw = body[/^#{Regexp.escape(heading)}\n(.*?)(?=\n#+ |\z)/m, 1] || ""
    squeeze(raw)
  end

  def body_of(path) = squeeze(File.read(path))

  def test_executor_ties_each_node_to_its_commit
    body = section(File.read(EXECUTOR), "## Your Responsibilities")

    assert_includes body, "**Commit each node**"
    assert_includes body, "A node without its commit is incomplete."
  end

  def test_executor_reports_each_node_s_findings
    assert_includes section(File.read(EXECUTOR), "## Completion Report"),
      "each with its commit and its findings"
  end

  def test_executor_runs_no_plastic_write
    assert_includes section(File.read(EXECUTOR), "## Your Responsibilities"),
      "You run no Plastic command that writes."
  end

  def test_planner_returns_the_plan_in_its_report
    assert_includes section(File.read(PLANNER), "## Your Responsibilities"),
      "You run no Plastic command that writes."
  end

  def test_planner_is_a_dispatched_node
    body = body_of(PLANNER)

    assert_includes body, "The main session dispatches you for one step"
    refute_includes body, "orchestrating session"
  end

  def test_agent_frontmatter_descriptions
    assert_equal <<~FRONT.strip, File.readlines(EXECUTOR, chomp: true)[0..7].join("\n")
      ---
      name: plastic-executor
      description: |
        Use for the Exec stage in auto mode: commit the plan's tests red, implement
        the nodes with a commit each, drive the test suite green, and report back.
      model: sonnet
      effort: medium
      ---
    FRONT

    assert_equal <<~FRONT.strip, File.readlines(PLANNER, chomp: true)[0..8].join("\n")
      ---
      name: plastic-planner
      description: |
        Use for one planning step in auto mode: draft the plan with its failure-mode
        matrix and proposed work nodes, or review a plan or a diff, and report
        back. The main session records the result.
      model: opus
      effort: medium
      ---
    FRONT
  end

  def test_internals_doc_names_the_tick_lag_warning
    body = body_of(INTERNALS)

    assert_includes body, "intent_ticks_lag"
    assert_match(/doctor scan includes/i, body)
  end
end
