# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/config"

class ConfigLayoutTest < Plastic::TestCase
  def layout(data) = Plastic::Config::Layout.new(data)

  def test_a_file_with_sections_is_already_in_the_layout
    data = { "version" => 3, "global" => { "statusline" => false } }

    assert_predicate layout(data), :sectioned?
    assert_equal data, layout(data).sections
  end

  def test_a_flat_file_moves_its_settings_under_global_and_keeps_the_version
    sections = layout({ "version" => 3, "statusline" => false, "agent" => { "parallel_mode" => "linear" } }).sections

    assert_equal({ "version" => 3, "global" => { "statusline" => false, "agent" => { "parallel_mode" => "linear" } } }, sections)
  end

  def test_the_agent_type_is_dropped
    assert_equal({ "global" => {} }, layout({ "agent" => { "type" => "codex" } }).sections)
  end

  def test_flat_and_claude_agent_models_move_to_the_claude_code_section
    data = { "agents" => { "models" => { "plastic-executor" => "haiku", "claude" => { "plastic-enforcer" => "sonnet" } } } }

    expected = { "plastic-executor" => "haiku", "plastic-enforcer" => "sonnet" }

    assert_equal expected, layout(data).sections.dig("harnesses", "claude-code", "agents", "models")
  end

  def test_codex_agent_efforts_move_to_the_codex_section
    data = { "agents" => { "efforts" => { "codex" => { "plastic-executor" => "high" } } } }

    assert_equal({ "global" => {}, "harnesses" => { "codex" => { "agents" => { "efforts" => { "plastic-executor" => "high" } } } } }, layout(data).sections)
  end

  def test_the_claude_advisor_default_moves_to_the_claude_code_section
    sections = layout({ "advisor" => { "enabled" => false, "claude" => { "default" => "plastic-secondary-advisor" } } }).sections

    assert_equal [{ "advisor" => { "enabled" => false } }, { "advisor" => { "default" => "plastic-secondary-advisor" } }],
      [sections["global"], sections.dig("harnesses", "claude-code")]
  end

  def test_an_empty_file_reads_as_an_empty_layout
    assert_equal({}, layout(nil).sections)
  end
end
