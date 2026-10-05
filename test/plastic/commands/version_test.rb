# frozen_string_literal: true

require_relative "installer_helper"

class VersionCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_reports_the_running_package_version_and_its_channel
    result = call("version", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("9.1.0-alpha.2") })

    assert_equal 0, result.code
    assert_match(/version:\s+9\.1\.0-alpha\.2/, result.out)
    assert_match(/channel:\s+alpha/, result.out)
  end

  def test_a_version_file_wins_over_the_package_manifest
    root = fake_package("9.1.0")
    File.write(File.join(root, "VERSION"), "9.2.0-beta.1\n")
    result = call("version", "--json", env: { "PLASTIC_PACKAGE_ROOT" => root })

    assert_equal "9.2.0-beta.1", JSON.parse(result.out).fetch("result").fetch("version")
  end

  def test_fails_when_the_package_has_no_version_file
    root = FileUtils.mkdir_p(File.join(@home, "empty")).first
    result = call("version", env: { "PLASTIC_PACKAGE_ROOT" => root })

    assert_equal 1, result.code
    assert_includes result.err, "no VERSION file and no package.json"
  end

  def test_reading_the_version_writes_nothing_under_the_home
    before = tree_snapshot(@plastic_home)
    call("version")

    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_the_installer_commands_ship_with_the_core_files
    require_relative "../../../scripts/lib/installer_core"
    files = InstallerCore.new(package_root: PACKAGE_ROOT).send(:core_files)

    %w[version install update rollback uninstall].each do |name|
      assert Plastic::CLI.find([name]), "plastic #{name} is missing from the command table"
      assert_includes files, "scripts/lib/plastic/commands/#{name}.rb"
    end
  end
end
