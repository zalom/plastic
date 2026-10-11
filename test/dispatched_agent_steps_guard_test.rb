# frozen_string_literal: true

require "minitest/autorun"

# A dispatched agent is a stateless node: the main session takes the lock,
# claims each node, records each result and closes the intent. No shipped
# agent file names one of those commands, or another Plastic write, as a step.
class DispatchedAgentStepsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SUBJECTS = Dir[File.join(ROOT, "agents", "*.md")].sort
  ORCHESTRATOR = /plastic auto\b|plastic intent (?:end|abandon|note|rule|verdict|approve)\b|plastic node \w+|node claim|plastic edge \w+|plastic session note|plastic sync\b|savepoint-note|insight-append/

  def orchestrator_steps(text) = text.each_line.with_index(1).filter_map { |line, number| "#{number}: #{line.strip}" if line.match?(ORCHESTRATOR) }

  def test_the_subjects_are_read_from_the_disk
    assert(SUBJECTS.any? { |path| path.end_with?("agents/plastic-executor.md") })
  end

  def test_no_agent_file_names_an_orchestrator_step
    found = SUBJECTS.to_h { |path| [path.delete_prefix("#{ROOT}/"), orchestrator_steps(File.read(path))] }.reject { |_, lines| lines.empty? }

    assert_empty found
  end

  def test_the_detector_catches_each_orchestrator_command
    ["Take the intent with plastic auto ID.", "Run plastic auto take 7.", "Close with plastic intent end ID.",
      "Run plastic node claim 7 n1.", "node claim it first", "Record plastic node done ID NODE TEXT.",
      "Add plastic edge add 7 n1 n2.", "plastic intent note ID TEXT", "scripts/insight-append DIR TEXT"]
      .each { |line| refute_empty orchestrator_steps(line), line }
  end

  def test_the_detector_leaves_a_read_command_alone
    assert_empty orchestrator_steps("Read the brief with plastic intent brief 7 and plastic graph show 7.")
  end
end
