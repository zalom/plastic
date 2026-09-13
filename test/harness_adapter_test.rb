# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "yaml"

require_relative "../scripts/lib/harness_adapter"

# HarnessAdapter (intent 340b, G7c, n1): the harness seam. Matrix rows
# 1.1, 1.3, 1.6-1.14, 1.18 in actions/ACTION_1.md n1 (1.2, 1.4-1.5, 1.19-1.32
# live in runner_cli_test.rb / runner_dispatch_test.rb / install_sync_test.rb).
class HarnessAdapterTest < Minitest::Test
  RETURN_CONTRACT = "RETURN CONTRACT: reply with exactly one YAML document as your final message.\n"

  ENTRY = {
    node: "n1", kind: "work", role: "executor", model: "sonnet",
    worktree: "/repo/.claude/worktrees/1--demo--n1",
    packet: "/store/1--demo/packets/n1--a1.packet",
  }.freeze

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  # --- 1.1: the key comes from config agent.type ------------------------------

  def test_key_comes_from_config
    assert_equal "codex", HarnessAdapter.resolve_key(config: { "agent" => { "type" => "codex" } })
    assert_equal "claude-code", HarnessAdapter.resolve_key(config: { "agent" => { "type" => "claude-code" } })
  end

  def test_key_defaults_to_claude_code_with_no_config
    assert_equal "claude-code", HarnessAdapter.resolve_key(config: {})
    assert_equal "claude-code", HarnessAdapter.resolve_key(config: nil)
  end

  # --- (feeds 1.2's CLI-level override) ---------------------------------------

  def test_override_wins_over_config_for_this_call
    key = HarnessAdapter.resolve_key(config: { "agent" => { "type" => "claude-code" } }, override: "codex")
    assert_equal "codex", key
  end

  # --- 1.3: an unknown key falls back to claude-code, with a warning ----------

  def test_unknown_key_falls_back_with_warning
    key = nil
    warning = capture_stderr { key = HarnessAdapter.resolve_key(config: { "agent" => { "type" => "hermes" } }) }
    assert_equal "claude-code", key
    assert_match(/hermes/, warning)
    assert_match(/claude-code/, warning)
  end

  def test_unknown_override_falls_back_with_warning
    key = nil
    warning = capture_stderr do
      key = HarnessAdapter.resolve_key(config: { "agent" => { "type" => "codex" } }, override: "pi-agent")
    end
    assert_equal "claude-code", key
    assert_match(/pi-agent/, warning)
  end

  # --- 1.6: the rendered block never runs together with the YAML plan --------

  def test_rendering_is_separate_from_yaml
    plan_yaml = YAML.dump("return_contract" => RETURN_CONTRACT,
                           "dispatch" => [{ "node" => "n1", "kind" => "work" }])
    block = HarnessAdapter.render([ENTRY], harness: "claude-code", return_contract: RETURN_CONTRACT)
    refute_nil block

    # If the rendered block ran directly beneath the plan with no boundary
    # between them (the failure this row names), a reader parsing the whole
    # thing as one YAML document would either raise or silently graft the
    # block's text onto the plan's own trailing scalar - never reproduce the
    # clean plan on its own.
    combined = "#{plan_yaml}#{block}"
    reparsed = begin
      YAML.safe_load(combined)
    rescue StandardError
      :raised
    end
    clean_plan = YAML.safe_load(plan_yaml)
    refute_equal clean_plan, reparsed,
                 "the rendered block must not be silently absorbed into the plan's own YAML document"
  end

  # --- 1.7-1.10: kind -> agent type --------------------------------------------

  def test_work_kind_maps_to_work_agent
    assert_equal "plastic-node-work", HarnessAdapter.agent_type_for_kind("work")
  end

  def test_verify_kind_maps_to_verify_agent
    assert_equal "plastic-node-verify", HarnessAdapter.agent_type_for_kind("verify")
  end

  def test_research_kind_maps_to_research_agent
    assert_equal "plastic-node-research", HarnessAdapter.agent_type_for_kind("research")
  end

  def test_unknown_kind_maps_to_work_agent
    assert_equal "plastic-node-work", HarnessAdapter.agent_type_for_kind("mystery")
  end

  def test_render_names_the_agent_type_per_kind
    dispatched = [
      ENTRY.merge(node: "n1", kind: "work"),
      ENTRY.merge(node: "n2", kind: "verify"),
      ENTRY.merge(node: "n3", kind: "research"),
    ]
    block = HarnessAdapter.render(dispatched, harness: "claude-code", return_contract: RETURN_CONTRACT)
    assert_match(/plastic-node-work/, block)
    assert_match(/plastic-node-verify/, block)
    assert_match(/plastic-node-research/, block)
  end

  # --- 1.11: the model comes from the plan, never a fresh lookup --------------

  def test_model_comes_from_the_plan
    block = HarnessAdapter.render([ENTRY.merge(kind: "verify", model: "opus")], harness: "claude-code",
                                   return_contract: RETURN_CONTRACT)
    assert_match(/opus/, block)
    refute_match(/sonnet/, block)
  end

  # --- 1.12: the packet path is the whole prompt -------------------------------

  def test_packet_path_is_the_prompt
    block = HarnessAdapter.render([ENTRY], harness: "claude-code", return_contract: RETURN_CONTRACT)
    assert_includes block, ENTRY[:packet]
  end

  # --- 1.13: the return contract renders once, never per node -----------------

  def test_return_contract_rendered_once
    dispatched = [ENTRY.merge(node: "n1"), ENTRY.merge(node: "n2")]
    block = HarnessAdapter.render(dispatched, harness: "claude-code", return_contract: RETURN_CONTRACT)
    assert_equal 1, block.scan(/RETURN CONTRACT/).length
  end

  # --- 1.14: an empty dispatch list renders nothing ----------------------------

  def test_empty_dispatch_renders_nothing
    assert_nil HarnessAdapter.render([], harness: "claude-code", return_contract: RETURN_CONTRACT)
    assert_nil HarnessAdapter.render(nil, harness: "claude-code", return_contract: RETURN_CONTRACT)
  end

  # --- the codex key renders its own, distinct block, never claude-code's ----

  def test_codex_renders_a_distinct_block
    claude = HarnessAdapter.render([ENTRY], harness: "claude-code", return_contract: RETURN_CONTRACT)
    codex = HarnessAdapter.render([ENTRY], harness: "codex", return_contract: RETURN_CONTRACT)
    refute_equal claude, codex
    assert_includes codex, ENTRY[:packet]
    refute_match(/plastic-node-work/, codex)
  end

  # --- 1.18: a config-authored key is squashed before it reaches the ledger --

  def test_harness_key_is_squashed_before_the_ledger
    key = HarnessAdapter.resolve_key(config: { "agent" => { "type" => "codex\ninjected" } })
    # A newline can never survive into the resolved key. Squashed, it never
    # equals a known key, so it falls back to the safe default rather than
    # reaching NodeLedger's own fields hash unsquashed - which raises
    # ArgumentError out of the dispatcher mid-dispatch, after the packet is
    # already built (this row's whole failure mode).
    assert_equal "claude-code", key
    refute_match(/[\t\n]/, key)
  end

  def test_harness_key_with_incidental_whitespace_still_resolves
    assert_equal "codex", HarnessAdapter.resolve_key(config: { "agent" => { "type" => " codex \n" } })
  end

  # --- 2.5 (intent 340a, G7b, n2): unattended start only where a Ruby loop
  # owns dispatch ------------------------------------------------------------

  def test_unattended_start_only_where_ruby_owns_dispatch
    assert HarnessAdapter.unattended_start?("codex")
    refute HarnessAdapter.unattended_start?("claude-code")
    refute HarnessAdapter.unattended_start?("some-unknown-harness")
    refute HarnessAdapter.unattended_start?(nil)
  end
end
