# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/preflight"
require_relative "../scripts/lib/sqlite3_dependency"

class PreflightTest < Minitest::Test
  def test_names_the_runtime_sqlite3_version_in_its_gem_install_instruction
    result = Preflight.check(ruby_version: "4.0.0", git_present: true, sqlite3_present: true,
      missing_gems: ["sqlite3"], platform: "darwin")

    assert_includes result.fetch(:messages).first, "next: gem install sqlite3 -v 2.9.6"
  end

  def test_rejects_a_loaded_sqlite3_gem_outside_the_runtime_pin
    refute Sqlite3Dependency.supported?("2.9.5")
    assert Sqlite3Dependency.supported?("2.9.6")
  end

  def test_reports_sqlite_availability_and_a_missing_library
    assert Sqlite3Dependency.available?

    with_kernel_require(->(_name) { raise LoadError, "sqlite unavailable" }) do
      refute Sqlite3Dependency.available?
    end
  end

  def test_keeps_generic_gem_install_instructions_for_other_dependencies
    assert_equal "gem install pg", Preflight.gem_install_command("pg")
  end

  def test_reports_a_missing_runtime_with_platform_specific_recovery_steps
    linux = Preflight.check(ruby_version: "3.4.0", git_present: false, sqlite3_present: false,
      missing_gems: ["sqlite3"], platform: "linux")
    mac = Preflight.check(ruby_version: "4.0.0", git_present: false, sqlite3_present: false,
      missing_gems: [], platform: "darwin")

    assert_equal [false, true], linux.values_at(:ok, :fatal)
    assert_includes linux.fetch(:messages).join("\n"), "sudo apt-get install -y git"
    assert_includes linux.fetch(:messages).join("\n"), "sudo apt-get install -y sqlite3"
    assert_includes mac.fetch(:messages).join("\n"), "xcode-select --install"
  end

  private

  def with_kernel_require(replacement)
    original = Kernel.instance_method(:require)
    Kernel.send(:define_method, :require, &replacement)
    yield
  ensure
    Kernel.send(:define_method, :require, original)
  end
end
