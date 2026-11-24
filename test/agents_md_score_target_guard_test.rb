# frozen_string_literal: true

require "minitest/autorun"

class AgentsMdScoreTargetGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def gate_minimum = File.read(File.join(ROOT, "bin/verify-change"))[/RUBYCRITIC_MINIMUM = (\d+)/, 1]

  def agents_md = File.read(File.join(ROOT, "AGENTS.md"))

  def test_the_gate_sets_a_minimum
    refute_nil gate_minimum
  end

  def test_agents_md_names_the_score_target_of_the_gate
    assert_match(/RubyCritic score of #{gate_minimum}\b[^.]*fails? nothing/, agents_md,
      "AGENTS.md does not name the RubyCritic score of #{gate_minimum} that bin/verify-change sets as a target")
  end
end
