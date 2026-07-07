# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "stringio"

require_relative "../scripts/lib/preflight"
require_relative "../scripts/install"

# Hermetic tests for the pure pre-flight decision table (intent 38) and for the
# `install.rb#preflight_gate` wiring around it. No eval, no ENV seam, no shelling
# out: every probe is injected.
class PreflightTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  EM_DASH = "—"
  EN_DASH = "–"

  # --- Ruby floor ---

  def test_ruby_below_floor_is_fatal_and_names_floor_and_mise_command
    result = Preflight.check(ruby_version: "2.6.10", node_version: "v20.0.0",
                              git_present: true, mise_present: true)
    assert result[:fatal]
    refute result[:ok]
    assert result[:messages].any? { |m| m.include?("3.0.0") }
    assert result[:messages].any? { |m| m.include?("mise use --global ruby@3.3") }
  end

  def test_ruby_missing_is_fatal_and_says_not_found
    result = Preflight.check(ruby_version: "", node_version: "v20.0.0",
                              git_present: true, mise_present: true)
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("not found") }
  end

  def test_ruby_at_or_above_floor_has_no_ruby_issue
    %w[3.0.0 3.3.5].each do |version|
      result = Preflight.check(ruby_version: version, node_version: "v20.0.0",
                                git_present: true, mise_present: true)
      refute result[:fatal]
      assert result[:messages].none? { |m| m.include?("Plastic needs Ruby") }
    end
  end

  # --- Node floor ---

  def test_node_below_floor_is_a_warning_with_pin_command
    result = Preflight.check(ruby_version: "3.3.0", node_version: "v16.20.0",
                              git_present: true, mise_present: true)
    refute result[:fatal]
    assert result[:messages].any? { |m| m.include?("node@25") }
  end

  def test_node_at_or_above_floor_has_no_node_issue
    %w[v18.19.0 v25.0.0].each do |version|
      result = Preflight.check(ruby_version: "3.3.0", node_version: version,
                                git_present: true, mise_present: true)
      assert result[:messages].none? { |m| m.include?("Plastic works best on Node") }
    end
  end

  # --- git presence ---

  def test_git_absent_is_a_warning
    result = Preflight.check(ruby_version: "3.3.0", node_version: "v20.0.0",
                              git_present: false, mise_present: true)
    refute result[:fatal]
    assert result[:messages].any? { |m| m.include?("git was not found") }
  end

  def test_git_present_has_no_git_issue
    result = Preflight.check(ruby_version: "3.3.0", node_version: "v20.0.0",
                              git_present: true, mise_present: true)
    assert result[:messages].none? { |m| m.include?("git was not found") }
  end

  # --- mise offer shape ---

  def test_mise_present_omits_the_install_mise_line
    result = Preflight.check(ruby_version: "2.6.10", node_version: "v20.0.0",
                              git_present: true, mise_present: true)
    assert result[:messages].none? { |m| m.include?("curl https://mise.run") }
  end

  def test_mise_absent_includes_the_install_mise_line
    result = Preflight.check(ruby_version: "2.6.10", node_version: "v20.0.0",
                              git_present: true, mise_present: false)
    assert result[:messages].any? { |m| m.include?("curl https://mise.run") }
  end

  # --- all good ---

  def test_all_good_probes_are_ok_with_no_messages
    result = Preflight.check(ruby_version: "3.3.5", node_version: "v25.0.0",
                              git_present: true, mise_present: true)
    assert result[:ok]
    refute result[:fatal]
    assert_empty result[:messages]
  end

  # --- hygiene ---

  def test_no_message_contains_em_or_en_dash
    scenarios = [
      { ruby_version: "2.6.10", node_version: "v16.20.0", git_present: false, mise_present: false },
      { ruby_version: "3.3.5", node_version: "v25.0.0", git_present: true, mise_present: true },
    ]
    scenarios.each do |probes|
      Preflight.check(**probes)[:messages].each do |message|
        refute_includes message, EM_DASH, "message contains an em-dash: #{message.inspect}"
        refute_includes message, EN_DASH, "message contains an en-dash: #{message.inspect}"
      end
    end
  end

  # --- mise.toml pin guard ---

  def test_mise_toml_pins_ruby_to_the_preflight_constant
    content = File.read(File.join(WORKTREE, "mise.toml"))
    assert_includes content, "ruby = \"#{Preflight::RUBY_PIN}\""
  end

  # --- install.rb#preflight_gate wiring ---

  def test_preflight_gate_returns_1_and_prints_the_offer_on_fatal_ruby
    install = Install.new(package_root: WORKTREE, plastic_home: Dir.mktmpdir("preflight-gate"))
    buf = StringIO.new
    result = install.preflight_gate(ruby_version: "2.6.10", node_version: "v20.0.0",
                                     git_present: true, mise_present: true, out: buf)
    assert_equal 1, result
    assert_includes buf.string, "mise use --global ruby@3.3"
  end

  def test_preflight_gate_returns_0_when_ruby_is_ok
    install = Install.new(package_root: WORKTREE, plastic_home: Dir.mktmpdir("preflight-gate"))
    buf = StringIO.new
    result = install.preflight_gate(ruby_version: "3.3.0", node_version: "v20.0.0",
                                     git_present: true, mise_present: true, out: buf)
    assert_equal 0, result
  end
end
