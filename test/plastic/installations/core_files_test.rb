# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/core_files"

class CoreFilesTest < Plastic::TestCase
  include InstallFixture

  def files = Plastic::Installations::CoreFiles.new(shipped).call

  def test_the_files_hold_the_launcher_the_root_files_and_each_name_maps_to_itself
    assert_equal({ "PLASTIC.md" => "PLASTIC.md", "exe/plastic" => "exe/plastic" }, files.slice("PLASTIC.md", "exe/plastic"))
  end

  def test_the_hooks_the_kernel_tree_and_the_help_chapters_come_from_the_disk
    assert_equal %w[docs/help/tutorial.md hooks/session-start hooks/statusline lib/plastic.rb lib/plastic/one.rb],
      files.keys.grep(%r{\A(?:docs|hooks|lib)/}).sort
  end

  def test_the_files_hold_no_script_and_no_bin_launcher
    assert_empty files.keys.grep(%r{\A(?:scripts|bin)/})
  end

  def test_the_real_package_ships_the_deprecations_file_and_every_kernel_file
    real = Plastic::Installations::CoreFiles.new(REAL_PACKAGE).call

    assert_equal ["deprecations.yml", "lib/plastic.rb"], real.keys & ["deprecations.yml", "lib/plastic.rb"]
  end
end
