# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/config"

class ConfigDocumentTest < Plastic::TestCase
  def path = File.join(@plastic_home, "config.yml")

  def document(text = nil)
    File.write(path, text) if text
    Plastic::Config::Document.new(path)
  end

  def saved = YAML.safe_load_file(path, aliases: true)

  def test_a_global_setting_is_written_under_global
    document("version: 3\n").set(%w[runner stop_hook], true)

    assert_equal({ "version" => 3, "global" => { "runner" => { "stop_hook" => true } } }, saved)
  end

  def test_a_harness_setting_is_written_under_its_section_only
    document("version: 3\n").set(%w[agents models plastic-executor], "haiku", harness: "codex")

    assert_equal({ "codex" => { "agents" => { "models" => { "plastic-executor" => "haiku" } } } }, saved["harnesses"])
  end

  def test_a_set_replaces_the_value_already_there
    document("global:\n  statusline: true\n").set(%w[statusline], false)

    assert_equal({ "statusline" => false }, saved["global"])
  end

  def test_an_anchor_in_the_file_stays_after_a_set
    text = "global:\n  agents: &shared\n    models:\n      plastic-executor: haiku\n" \
           "harnesses:\n  claude-code:\n    agents: *shared\n"
    document(text).set(%w[statusline], false)

    assert_includes File.read(path), "&shared"
    assert_equal "haiku", saved.dig("harnesses", "claude-code", "agents", "models", "plastic-executor")
  end

  def test_a_flat_file_is_rewritten_in_the_layout_before_the_set
    document("agent:\n  type: codex\nstatusline: true\n").set(%w[screens], false)

    assert_equal({ "global" => { "statusline" => true, "screens" => false } }, saved)
  end

  def test_a_missing_file_is_created_with_the_setting
    document.set(%w[statusline], false)

    assert_equal({ "global" => { "statusline" => false } }, saved)
  end

def test_a_section_that_holds_no_mapping_takes_the_setting_as_its_mapping
  document("global: 5\n").set(%w[runner stop_hook], true)

  assert_equal({ "global" => { "runner" => { "stop_hook" => true } } }, saved)
end

def test_a_file_that_holds_no_mapping_is_written_as_the_sections
  document("- a\n").set(%w[statusline], false)

  assert_equal({ "global" => { "statusline" => false } }, saved)
end

def test_an_empty_file_takes_the_setting
  document("").set(%w[statusline], false)

  assert_equal({ "global" => { "statusline" => false } }, saved)
end

  def test_migrate_rewrites_a_flat_file_and_reports_it
    assert document("statusline: true\n").migrate
    assert_equal({ "global" => { "statusline" => true } }, saved)
  end

  def test_migrate_leaves_a_file_in_the_layout_alone
    refute document("global:\n  statusline: true\n").migrate
  end
end
