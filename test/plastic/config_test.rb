# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/config"
require "tmpdir"

class ConfigTest < Plastic::TestCase
  def config(text)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.yml"), text)
      yield Plastic::Config.new(dir)
    end
  end

  def test_a_true_flag_arms_the_gate
    config("runner:\n  stop_hook: true\n") { |cfg| assert cfg.flag(%w[runner stop_hook], default: false) }
  end

  def test_the_string_false_does_not_arm_the_gate
    config("runner:\n  stop_hook: \"false\"\n") { |cfg| refute cfg.flag(%w[runner stop_hook], default: true) }
  end

  def test_a_value_that_is_not_a_boolean_reads_as_the_default
    config("statusline: maybe\n") { |cfg| assert_equal "x", cfg.flag(%w[statusline], default: "x") }
  end

  def test_a_missing_key_reads_as_the_default
    config("runner:\n  stop_hook: true\n") { |cfg| assert_equal "x", cfg.flag(%w[other key], default: "x") }
  end

  def test_a_missing_file_reads_as_the_default
    Dir.mktmpdir { |dir| refute Plastic::Config.new(dir).flag(%w[runner stop_hook], default: false) }
  end

  def test_a_file_that_does_not_parse_falls_back_to_the_default
    config("runner: [\n") { |cfg| refute cfg.flag(%w[runner stop_hook], default: false) }
  end

  def test_a_file_holding_a_plain_list_falls_back_to_the_default
    config("- a\n- b\n") { |cfg| refute cfg.flag(%w[runner stop_hook], default: false) }
  end

  def test_a_missing_choice_reads_as_the_default
    config("runner:\n  stop_hook: true\n") { |cfg| assert_equal "required", cfg.choice(%w[review pull_request], default: "required", allowed: %w[required off]) }
  end

  def test_an_allowed_choice_is_read
    config("review:\n  pull_request: off\n") { |cfg| assert_equal "off", cfg.choice(%w[review pull_request], default: "required", allowed: %w[required off]) }
  end

  def test_an_unknown_choice_reads_as_the_default
    config("review:\n  pull_request: sometimes\n") { |cfg| assert_equal "required", cfg.choice(%w[review pull_request], default: "required", allowed: %w[required off]) }
  end

  def test_a_missing_file_reads_the_choice_default
    Dir.mktmpdir { |dir| assert_equal "required", Plastic::Config.new(dir).choice(%w[review pull_request], default: "required", allowed: %w[required off]) }
  end

  def harness_config(text, harness)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.yml"), text)
      yield Plastic::Config.new(dir, harness:)
    end
  end

  def test_a_global_value_is_read_for_every_harness
    harness_config("global:\n  statusline: false\n", "codex") { |cfg| refute cfg.flag(%w[statusline], default: true) }
  end

  def test_a_harness_section_overrides_the_global_value_for_that_harness
    text = "global:\n  statusline: false\nharnesses:\n  claude-code:\n    statusline: true\n"

    harness_config(text, "claude-code") { |cfg| assert cfg.flag(%w[statusline], default: false) }
    harness_config(text, "codex") { |cfg| refute cfg.flag(%w[statusline], default: true) }
  end

  def test_a_harness_section_does_not_reach_the_global_reading
    config("harnesses:\n  codex:\n    statusline: false\n") { |cfg| assert cfg.flag(%w[statusline], default: true) }
  end

  def test_each_harness_reads_its_own_shipped_agent_models
    harness_config("version: 3\n", "claude-code") { |cfg| assert_equal "sonnet", cfg.value("agents.models.plastic-executor") }
    harness_config("version: 3\n", "codex") { |cfg| assert_equal "gpt-6-astra", cfg.value("agents.models.plastic-primary-advisor") }
  end

  def test_anchors_and_merge_keys_are_read
    text = "global:\n  agents: &shared\n    models:\n      plastic-executor: haiku\n" \
           "harnesses:\n  claude-code:\n    agents:\n      <<: *shared\n"

    harness_config(text, "claude-code") { |cfg| assert_equal "haiku", cfg.value("agents.models.plastic-executor") }
  end

  def test_a_flat_file_reads_as_the_sections_it_migrates_to
    text = "agent:\n  type: codex\n  parallel_mode: linear\nagents:\n  models:\n    plastic-executor: haiku\n    codex:\n      plastic-executor: gpt-x\n"

    harness_config(text, "claude-code") { |cfg| assert_equal %w[haiku linear], [cfg.value("agents.models.plastic-executor"), cfg.value("agent.parallel_mode")] }
    harness_config(text, "codex") { |cfg| assert_equal ["gpt-x", nil], [cfg.value("agents.models.plastic-executor"), cfg.value("agent.type")] }
  end

  def test_the_overrides_hold_only_what_the_file_sets
    text = "global:\n  advisor:\n    enabled: false\nharnesses:\n  codex:\n    agents:\n      models:\n        plastic-executor: gpt-x\n"

    expected = { "advisor" => { "enabled" => false }, "agents" => { "models" => { "plastic-executor" => "gpt-x" } } }

    harness_config(text, "codex") { |cfg| assert_equal expected, cfg.overrides }
  end

  def test_the_entries_name_each_setting_by_its_dotted_key
    harness_config("global:\n  runner:\n    stop_hook: true\n", "claude-code") do |cfg|
      assert_equal [true, "opus"], cfg.entries.values_at("runner.stop_hook", "agents.models.plastic-planner")
    end
  end

  def test_the_global_entries_hold_no_harness_setting
    config("version: 3\n") { |cfg| refute cfg.entries.key?("agents.models.plastic-executor") }
  end

  def test_an_unregistered_harness_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { Plastic::Config.new(@plastic_home, harness: "cursor") }
  end
end
