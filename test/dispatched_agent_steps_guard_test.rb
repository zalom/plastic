# frozen_string_literal: true

require "minitest/autorun"

# A dispatched agent is a stateless node: the main session claims the node,
# claims each node, records each result and closes the intent. No shipped
# agent file names one of those commands, or another Plastic write, as a step.
class DispatchedAgentStepsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # The driver role is the one agent that runs the graph loop, so it names these commands by design.
  DRIVER = File.join(ROOT, "agents", "plastic-driver.md")
  SUBJECTS = (Dir[File.join(ROOT, "agents", "*.md")] - [DRIVER]).sort
  ORCHESTRATOR = /plastic (?:roadmap )?auto\b|plastic intent (?:end|abandon|note|rule|verdict|approve|start|auto|park)\b|plastic node (?!(?:claim|done|fail)\b)\w+|(?<!plastic )node claim|plastic edge \w+|plastic session note|plastic sync\b|savepoint-note|insight-append/

  def orchestrator_steps(text) = text.each_line.with_index(1).filter_map { |line, number| "#{number}: #{line.strip}" if line.match?(ORCHESTRATOR) }

  def test_the_subjects_are_read_from_the_disk
    assert(SUBJECTS.any? { |path| path.end_with?("agents/plastic-executor.md") })
  end

  def test_the_driver_role_is_the_one_agent_left_out
    assert_path_exists DRIVER
    refute_includes SUBJECTS, DRIVER
  end

  def test_no_agent_file_names_an_orchestrator_step
    found = SUBJECTS.to_h { |path| [path.delete_prefix("#{ROOT}/"), orchestrator_steps(File.read(path))] }.reject { |_, lines| lines.empty? }

    assert_empty found
  end

  def test_the_detector_catches_each_orchestrator_command
    ["Take the intent with plastic auto ID.", "Run plastic auto take 7.", "Close with plastic intent end ID.",
      "node claim it first", "Record plastic node resolve ID NODE TEXT.",
      "Start it with plastic intent start 7.", "Deliver it with plastic intent auto 7.", "Pick with plastic roadmap auto r1.",
      "Add plastic edge add 7 n1 n2.", "plastic intent note ID TEXT", "scripts/insight-append DIR TEXT"]
      .each { |line| refute_empty orchestrator_steps(line), line }
  end

  def test_the_detector_leaves_the_handed_node_commands_alone
    ["Run plastic node claim ID NODE.", "Finish with plastic node done ID NODE TEXT --output PATH.", "Or plastic node fail ID NODE TEXT."]
      .each { |line| assert_empty orchestrator_steps(line), line }
  end

  def test_the_detector_still_catches_every_other_node_command
    ["plastic node ask ID NODE TEXT", "plastic node impede ID NODE TEXT", "plastic node add ID TITLE", "plastic node release ID NODE"]
      .each { |line| refute_empty orchestrator_steps(line), line }
  end

  def test_the_worker_roles_name_the_handed_node_exception
    %w[plastic-planner plastic-executor].each do |name|
      assert_includes File.read(File.join(ROOT, "agents", "#{name}.md")), "**A node a driver hands you.**"
    end
  end

  def test_the_detector_leaves_a_read_command_alone
    assert_empty orchestrator_steps("Read the brief with plastic intent brief 7 and plastic graph show 7.")
  end
end
