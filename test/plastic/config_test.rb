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
end
