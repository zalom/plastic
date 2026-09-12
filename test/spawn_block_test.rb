# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/runner_dispatch"
require_relative "../scripts/lib/runner_policy"

# The spawn block RunnerDispatch prints per dispatched node (355, n6, D8):
# harness-neutral text a session pastes into the Agent tool, and the two
# skill paragraphs that make a lead session optional for a graph delivery.
# Matrix rows 6.5-6.7 in nodes/n6.md.
class SpawnBlockTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # --- 6.5: the block never names a harness ----------------------------------

  def test_block_is_harness_neutral
    block = RunnerDispatch.spawn_block(model: RunnerPolicy.model_for("work"), packet: "/tmp/n1--abc.packet",
                                        test_command: "test command: ruby bin/test --only test/x_test.rb",
                                        call_cap: RunnerPolicy.call_cap("work"))

    refute_match(/claude/i, block, "the spawn block must never name a harness by name: #{block}")
    refute_match(/codex/i, block, "the spawn block must never name a harness by name: #{block}")
    assert_includes block, "agent: #{RunnerDispatch::SPAWN_AGENT}"
  end

  # --- 6.6: the auto skill says a lead is optional for a graph delivery -----

  def test_auto_skill_says_lead_optional
    text = File.read(File.join(ROOT, "skills", "auto", "SKILL.md"))

    assert_match(/lead is a choice/i, text, "the auto skill must say a lead is optional")
    assert_match(/decision node/i, text,
                 "the auto skill must name graphs with decision nodes as where a lead earns its keep")
  end

  # --- 6.7: the executing skill names the paste as the dispatch step --------

  def test_executing_skill_names_the_paste
    text = File.read(File.join(ROOT, "skills", "intent-executing", "SKILL.md"))

    assert_match(/paste/i, text, "the executing skill must name the paste into the Agent tool as the dispatch step")
    assert_match(/spawn block/i, text, "the executing skill must name the spawn block runner step prints")
  end
end
