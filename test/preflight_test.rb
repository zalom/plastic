# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "stringio"

require_relative "../scripts/lib/preflight"
require_relative "../scripts/install"

# Hermetic tests for the pure pre-flight decision table (intent 38, narrowed to
# git and sqlite3 by intent 391) and for the `install.rb#preflight_gate` wiring
# around it, plus isolated executable probes.
class PreflightTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  EM_DASH = "—"
  EN_DASH = "–"

  def check(overrides = {})
    defaults = { ruby_version: "4.0.1", git_present: true, sqlite3_present: true, platform: "darwin" }
    Preflight.check(**defaults.merge(overrides))
  end

  # --- Ruby floor ---

  def test_ruby_below_floor_is_fatal_and_names_floor_and_mise_command
    result = check(ruby_version: "2.6.10")
    assert result[:fatal]
    refute result[:ok]
    assert result[:messages].any? { |m| m.include?("4.0.0") }
    assert result[:messages].any? { |m| m.include?("mise use --global ruby@4.0") }
  end

  def test_ruby_missing_is_fatal_and_says_not_found
    result = check(ruby_version: "")
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("not found") }
  end

  def test_ruby_at_or_above_floor_has_no_ruby_issue
    %w[4.0.0 4.0.1].each do |version|
      result = check(ruby_version: version)
      refute result[:fatal]
      assert result[:messages].none? { |m| m.include?("Plastic needs Ruby") }
    end
  end

  def test_ruby_below_the_floor_of_four_is_fatal
    %w[3.0.0 3.4.7].each do |version|
      result = check(ruby_version: version)
      assert result[:fatal], "Ruby #{version} must not pass"
    end
  end

  # --- git presence: now fatal ---

  def test_git_absent_is_fatal_and_names_the_install_command_darwin
    result = check(git_present: false, platform: "darwin")
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("git was not found") }
    assert result[:messages].any? { |m| m.include?("xcode-select --install") }
  end

  def test_git_absent_is_fatal_and_names_the_install_command_linux
    result = check(git_present: false, platform: "linux")
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("sudo apt-get install -y git") }
  end

  def test_git_present_has_no_git_issue
    result = check(git_present: true)
    assert result[:messages].none? { |m| m.include?("git was not found") }
  end

  # --- sqlite3 presence: fatal ---

  def test_sqlite3_absent_is_fatal_and_names_the_install_command_darwin
    result = check(sqlite3_present: false, platform: "darwin")
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("sqlite3 was not found") }
    assert result[:messages].any? { |m| m.include?("xcode-select --install") }
  end

  def test_sqlite3_absent_is_fatal_and_names_the_install_command_linux
    result = check(sqlite3_present: false, platform: "linux")
    assert result[:fatal]
    assert result[:messages].any? { |m| m.include?("sudo apt-get install -y sqlite3") }
  end

  def test_sqlite3_present_has_no_sqlite3_issue
    result = check(sqlite3_present: true)
    assert result[:messages].none? { |m| m.include?("sqlite3 was not found") }
  end

  # --- node and mise probes are gone ---

  def test_check_takes_no_node_or_mise_keyword
    parameters = Preflight.method(:check).parameters.map { |_, name| name }
    refute_includes parameters, :node_version
    refute_includes parameters, :mise_present
  end

  def test_install_preflight_gate_has_no_node_version_keyword
    parameters = Install.instance_method(:preflight_gate).parameters.map { |_, name| name }
    refute_includes parameters, :node_version
    refute_includes parameters, :mise_present
  end

  # --- all good ---

  def test_all_good_probes_are_ok_with_no_messages
    result = check(ruby_version: "4.0.1", git_present: true, sqlite3_present: true)
    assert result[:ok]
    refute result[:fatal]
    assert_empty result[:messages]
  end

  # --- hygiene ---

  def test_no_message_contains_em_or_en_dash
    scenarios = [
      { ruby_version: "2.6.10", git_present: false, sqlite3_present: false, platform: "linux" },
      { ruby_version: "4.0.1", git_present: true, sqlite3_present: true, platform: "darwin" },
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

  def test_executable_probes_work_without_an_external_command_program
    Dir.mktmpdir("preflight-probes") do |dir|
      %w[git sqlite3].each do |name|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\nprintf 'test version\\n'\n")
        File.chmod(0o755, path)
      end
      install = Install.new(package_root: WORKTREE, plastic_home: dir)
      original_path = ENV["PATH"]
      begin
        ENV["PATH"] = dir
        assert install.send(:git_probe)
        assert install.send(:sqlite3_probe)
      ensure
        ENV["PATH"] = original_path
      end
    end
  end

  def test_preflight_gate_returns_1_and_prints_the_offer_on_fatal_ruby
    install = Install.new(package_root: WORKTREE, plastic_home: Dir.mktmpdir("preflight-gate"))
    buf = StringIO.new
    result = install.preflight_gate(ruby_version: "2.6.10", git_present: true, sqlite3_present: true,
                                     platform: "darwin", out: buf)
    assert_equal 1, result
    assert_includes buf.string, "mise use --global ruby@4.0"
  end

  def test_preflight_gate_returns_0_when_all_present
    install = Install.new(package_root: WORKTREE, plastic_home: Dir.mktmpdir("preflight-gate"))
    buf = StringIO.new
    result = install.preflight_gate(ruby_version: "4.0.0", git_present: true, sqlite3_present: true,
                                     platform: "darwin", out: buf)
    assert_equal 0, result
  end

  def test_preflight_gate_returns_1_and_names_command_when_git_absent
    install = Install.new(package_root: WORKTREE, plastic_home: Dir.mktmpdir("preflight-gate"))
    buf = StringIO.new
    result = install.preflight_gate(ruby_version: "4.0.0", git_present: false, sqlite3_present: true,
                                     platform: "linux", out: buf)
    assert_equal 1, result
    assert_includes buf.string, "sudo apt-get install -y git"
  end
end
