# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class CliPackageBinTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def package
    @package ||= JSON.parse(File.read(File.join(ROOT, "package.json")))
  end

  def test_the_package_cannot_be_published_to_a_registry
    assert package.fetch("private")
  end

  def test_the_package_names_no_registry_launcher
    refute package.key?("bin")
  end

  def test_the_launcher_exists_and_is_executable
    assert File.executable?(File.join(ROOT, "bin", "plastic"))
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
