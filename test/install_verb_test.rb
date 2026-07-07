require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/install"

# install verb orchestration: fresh vs refuse vs --reinstall, and ledger action (intent 30a1a).
# File-sync internals (distribute/install_for_agent) are covered by installer_core /
# install_packaging tests; here we stub them to isolate the verb's decision logic.
class InstallVerbTest < Minitest::Test
  class FakeInstall < Install
    attr_reader :distributed, :bootstrapped
    def distribute(mode) = (@distributed = mode)
    def bootstrap = (@bootstrapped = true)
    def install_for_agent(key, _force, **) = { agent: key, success: true, files: 1 }
  end

  def setup
    @home = Dir.mktmpdir("install-verb")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def build
    FakeInstall.new(package_root: ".", plastic_home: @home, version: "1.0.0-alpha.18")
  end

  def mark_installed(v = "1.0.0-alpha.18")
    File.write(File.join(@home, "VERSION"), "#{v}\n")
  end

  def test_fresh_install_bootstraps_and_logs_install
    i = build
    refute i.installed?
    i.run(selected: ["claude"])

    assert i.bootstrapped, "fresh install must bootstrap the store"
    assert_equal :install, i.distributed
    assert_equal "install", i.ledger_current["action"]
    assert_equal "1.0.0-alpha.18", i.ledger_current["version"]
  end

  def test_refuse_when_already_installed
    mark_installed
    i = build
    status = nil
    _out, err = capture_io { status = i.cli(["--claude"]) }
    assert_equal 1, status, "install must refuse when already installed"
    assert_empty i.ledger_read, "a refused install writes nothing to the ledger"
    assert_match(/already installed/i, err)
  end

  def test_reinstall_resyncs_without_bootstrap_and_logs_reinstall
    mark_installed
    i = build
    i.run(selected: ["claude"], reinstall: true)

    assert_nil i.bootstrapped, "reinstall must NOT bootstrap (store is preserved)"
    assert_equal :update, i.distributed, "reinstall re-syncs, no fresh bootstrap"
    assert_equal "reinstall", i.ledger_current["action"]
  end

  def test_ledger_action_override_records_update
    mark_installed
    i = build
    i.run(selected: ["claude"], reinstall: true, ledger_action: "update")
    assert_equal "update", i.ledger_current["action"],
      "update/versions delegate here and override the recorded action"
  end

  def test_results_point_at_first_guide
    i = build
    out, _err = capture_io { i.run(selected: ["claude"]) }
    assert_match "docs/guides/your-first-intent-in-10-minutes.md", out,
      "the install results must point a first-time user at guide 1"
  end
end
