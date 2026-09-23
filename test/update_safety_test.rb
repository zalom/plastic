# frozen_string_literal: true

require_relative "test_helper"
require_relative "../scripts/update"
require_relative "../scripts/rollback"
require "tmpdir"
require "open3"
require "rbconfig"

class UpdateSafetyTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("update-safety")
    FileUtils.mkdir_p(File.join(@home, "stores", "global", "store"))
    File.write(File.join(@home, "VERSION"), "2.0.1\n")
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def test_downloaded_cli_uses_its_own_package_despite_old_updater_environment
    bin = File.expand_path("../bin/plastic", __dir__)
    out, err, status = Open3.capture3({"HOME" => @home, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => File.join(@home, "tmp"), "PLASTIC_PACKAGE_ROOT" => File.join(@home, "old-package")},
      RbConfig.ruby, bin, "version", "--json")

    assert_predicate status, :success?, err
    assert_includes out, JSON.parse(File.read(File.expand_path("../package.json", __dir__))).fetch("version")
  end

  def test_update_refuses_incompatible_channel_before_switch
    update = Update.new(package_root: ".", plastic_home: @home, version: "2.0.1")
    update.define_singleton_method(:fetch_dist_tags) { {"beta" => "1.10.0"} }
    switched = false
    update.define_singleton_method(:perform_switch) { |*|
      switched = true
      0
    }
    _, err = capture_io { assert_equal 3, update.cli(%w[--beta --yes]) }

    refute switched
    assert_equal "Plastic 1.10.0 cannot read stores/ in #{@home}. Keep a version that supports this layout.\n", err
    assert_equal "2.0.1\n", File.read(File.join(@home, "VERSION"))
  end

  def test_rollback_refuses_incompatible_target_before_hooks_are_removed
    rollback = Rollback.new(package_root: ".", plastic_home: @home, version: "2.0.1")
    rollback.define_singleton_method(:system) { |*| false }
    prepared = false
    rollback.define_singleton_method(:prepare_switch) { |*| prepared = true }

    capture_io { assert_equal 3, rollback.switch_to("1.14.1", "2.0.1") }
    refute prepared
  end

  def test_store_layout_compatibility_boundary
    core = InstallerCore.new(package_root: ".", plastic_home: @home, version: "2.0.1")

    refute core.store_layout_compatible?("2.0.0-alpha.27")
    assert core.store_layout_compatible?("2.0.0-alpha.28")

    FileUtils.remove_entry(File.join(@home, "stores"))

    assert core.store_layout_compatible?("1.14.1")
  end

  def test_successful_process_with_wrong_installed_version_is_not_a_successful_update
    update = Update.new(package_root: ".", plastic_home: @home, version: "2.0.1")
    committed = false
    update.define_singleton_method(:commit_core_files) { |*| committed = true }
    update.define_singleton_method(:fetch_dist_tags) { {"latest" => "2.0.2"} }
    update.define_singleton_method(:system) { |*| true }

    _, error = capture_io do
      assert_equal 1, update.cli(["--codex"])
    end

    assert_equal %(Update did not install 2.0.2; installed version is "2.0.1".\n), error
    refute committed
  end

  def test_rollback_checks_the_version_after_the_installer_succeeds
    rollback = Rollback.new(package_root: ".", plastic_home: @home, version: "2.0.1", agents: [])
    calls = []
    rollback.define_singleton_method(:system) do |*args|
      calls << args
      true
    end

    capture_io { assert_equal 1, rollback.switch_to("2.0.0", "2.0.1") }
    assert_equal({"PLASTIC_PACKAGE_ROOT" => nil}, calls.first.first)
    assert_equal ["npx", "@zalom/plastic@2.0.0", "install", "--reinstall", "--ledger-action", "downgrade", "--claude"], calls.first.drop(1)
  end

  def test_rollback_accepts_a_verified_compatible_install
    rollback = Rollback.new(package_root: ".", plastic_home: @home, version: "2.0.1", agents: [])
    version = File.join(@home, "VERSION")
    rollback.define_singleton_method(:system) do |*|
      File.write(version, "2.0.0")
      true
    end

    capture_io { assert_equal 0, rollback.switch_to("2.0.0", "2.0.1") }
    assert_equal "2.0.0", File.read(version)
  end

  def test_rollback_reports_a_failed_installer
    rollback = Rollback.new(package_root: ".", plastic_home: @home, version: "2.0.1", agents: [])
    rollback.define_singleton_method(:system) { |*| false }

    capture_io { assert_equal 1, rollback.switch_to("2.0.0", "2.0.1") }
    assert_equal "2.0.1\n", File.read(File.join(@home, "VERSION"))
  end
end
