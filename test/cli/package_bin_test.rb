# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class CliPackageBinTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def package
    @package ||= JSON.parse(File.read(File.join(ROOT, "package.json")))
  end

  def test_the_npm_bin_entry_names_the_ruby_launcher
    assert_equal({"plastic" => "bin/plastic"}, package.fetch("bin"))
  end

  def test_the_npm_bin_entry_points_at_a_file_that_exists
    assert_path_exists File.join(ROOT, package.fetch("bin").fetch("plastic"))
  end

  def test_the_npm_bin_entry_points_at_an_executable
    assert File.executable?(File.join(ROOT, package.fetch("bin").fetch("plastic")))
  end

  def test_the_javascript_shim_is_gone
    refute_path_exists File.join(ROOT, "bin", "plastic.js")
  end

  def test_the_package_still_ships_the_launcher_directory
    assert_includes package.fetch("files"), "bin/"
  end

  def test_the_package_still_ships_the_scripts_the_launcher_calls
    assert_includes package.fetch("files"), "scripts/"
  end

  def test_the_package_still_ships_the_instruction_file
    assert_includes package.fetch("files"), "PLASTIC.md"
  end
end
