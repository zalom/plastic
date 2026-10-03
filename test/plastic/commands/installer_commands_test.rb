# frozen_string_literal: true

require "json"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/installer_core"

class InstallerCommandsTest < Plastic::TestCase
  COMMANDS = %w[version install update rollback uninstall].freeze

  def call(*argv, env: {})
    plastic(*argv, env:, table: Plastic::CLI::TABLE)
  end

  def test_public_installer_commands_are_shipped_and_registered
    COMMANDS.each { |name| assert Plastic::CLI.find([name]), "plastic #{name} is missing from the command table" }

    files = InstallerCore.new(package_root: File.expand_path("../../..", __dir__)).send(:core_files)
    COMMANDS.each do |name|
      assert_includes files, "scripts/lib/plastic/commands/#{name}.rb"
    end
  end

  def test_version_reports_the_shipped_version_as_text_and_json
    text = call("version")
    json = call("version", "--json")

    assert_equal 0, text.code
    assert_match(/version:\s+2\.0\.3/, text.out)
    assert_equal "2.0.3", JSON.parse(json.out).fetch("result").fetch("version")
  end

  def test_install_and_update_dry_runs_plan_without_changing_an_absent_or_populated_home
    [File.join(@home, "absent", ".plastic"), @plastic_home].each do |home|
      FileUtils.mkdir_p(home) if home == @plastic_home
      File.write(File.join(home, "user-note"), "keep\n") if home == @plastic_home
      before = tree_snapshot(home)

      %w[install update].each do |verb|
        result = call(verb, "--dry-run", env: { "PLASTIC_HOME" => home })

        assert_equal 0, result.code
        assert_match(/preview:\s+#{verb}/, result.out)
        assert_equal before, tree_snapshot(home)
      end
    end
  end

  def test_install_and_update_refuse_before_writes_without_a_verified_manifest
    %w[install update].each do |verb|
      before = tree_snapshot(@plastic_home)
      result = call(verb)

      assert_equal 3, result.code
      assert_includes result.err, "verified release manifest"
      assert_equal before, tree_snapshot(@plastic_home)
    end
  end

  private

  def tree_snapshot(path)
    return [] unless Dir.exist?(path)

    Dir.chdir(path) do
      Dir.glob("**/*", File::FNM_DOTMATCH).reject { |entry| [".", ".."].include?(entry) }.sort.map do |entry|
        File.file?(entry) ? [entry, File.binread(entry)] : [entry, :directory]
      end
    end
  end
end
