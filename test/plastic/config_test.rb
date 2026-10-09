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
end
