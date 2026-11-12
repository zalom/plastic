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

  SHIPPED_SCRIPTS = %w[
    scripts/install-release scripts/install.rb scripts/select-update-target
    scripts/lib/installer_release.rb scripts/lib/installer_release/ scripts/lib/installer_core.rb
    scripts/lib/agent_models.rb scripts/lib/hook_registry.rb scripts/lib/compact_instructions.rb
    scripts/lib/engine_permissions.rb scripts/lib/preflight.rb scripts/lib/store_layout.rb
    scripts/lib/version_number.rb scripts/lib/release_channels.rb
  ].freeze

  def test_the_launcher_exists_and_is_executable
    assert File.executable?(File.join(ROOT, "exe", "plastic"))
  end

  def test_the_package_ships_the_exe_folder_and_no_bin_entry
    assert_includes package.fetch("files"), "exe/"
    assert_empty package.fetch("files").grep(%r{\Abin/?})
  end

  def test_the_package_lists_the_scripts_it_ships_one_by_one
    assert_equal SHIPPED_SCRIPTS.sort, package.fetch("files").grep(%r{\Ascripts/}).sort
  end

  def test_the_listed_scripts_exist
    assert_empty(SHIPPED_SCRIPTS.reject { |path| File.exist?(File.join(ROOT, path)) })
  end

  def test_scripts_holds_only_what_the_package_lists
    held = Dir.glob("scripts/**/*", base: ROOT).select { |path| File.file?(File.join(ROOT, path)) }
    listed = held.select { |path| SHIPPED_SCRIPTS.any? { |entry| path == entry || (entry.end_with?("/") && path.start_with?(entry)) } }

    assert_empty held - listed
  end

  def test_the_package_ships_neither_a_release_tool_nor_a_development_script
    refute(package.fetch("files").any? { |path| path.match?(%r{build-release|release-check|release_(build|guard|archive)|\Abin/}) })
  end

  def test_the_package_still_ships_the_instruction_file
    assert_includes package.fetch("files"), "PLASTIC.md"
  end
end
