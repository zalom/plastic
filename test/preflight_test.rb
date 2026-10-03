# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/preflight"

class PreflightTest < Minitest::Test
  def test_names_the_gem_install_instruction_for_a_missing_gem
    result = Preflight.check(ruby_version: "4.0.0", git_present: true, sqlite3_present: true,
      missing_gems: ["sqlite3"], platform: "darwin")

    assert_includes result.fetch(:messages).first, "next: gem install sqlite3"
  end

  def test_reports_a_missing_runtime_with_platform_specific_recovery_steps
    linux = Preflight.check(ruby_version: "3.4.0", git_present: false, sqlite3_present: false,
      missing_gems: ["sqlite3"], platform: "linux")

    assert_equal [false, true], linux.values_at(:ok, :fatal)
    text = linux.fetch(:messages).join("\n")
    assert_includes text, "install git with your distribution's package manager"
    assert_includes text, "install sqlite3 with your distribution's package manager"
    refute_includes text, "apt-get"
  end

  def test_reports_macos_recovery_steps
    mac = Preflight.check(ruby_version: "4.0.0", git_present: false, sqlite3_present: false,
      missing_gems: [], platform: "darwin")

    assert_includes mac.fetch(:messages).join("\n"), "xcode-select --install"
  end
end
