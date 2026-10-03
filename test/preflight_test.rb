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
end
