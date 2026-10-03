# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../scripts/install"

class InstallerRuntimeTest < Minitest::Test
  class Probe < Install
    attr_accessor :gate, :selected, :registered, :runs

    def initialize(home)
      super(package_root: File.expand_path("..", __dir__), plastic_home: home, version: "2.1.0")
      @gate = 0
      @selected = []
      @registered = []
      @runs = []
    end

    def preflight_gate(*) = gate
    def agent_keys_from(*) = selected
    def prompt_agents = selected
    def agent_installed?(key) = registered.include?(key)
    def run(**arguments) = runs << arguments
  end

  def test_stops_before_selection_when_the_preflight_fails
    with_probe do |installer|
      installer.gate = 1

      assert_equal 1, installer.cli(["--claude"])
      assert_empty installer.runs
    end
  end

  def test_returns_without_writing_when_no_agent_is_selected
    with_probe do |installer|
      output, = capture_io { assert_equal 0, installer.cli([]) }

      assert_includes output, "No agents selected"
      assert_empty installer.runs
    end
  end

  def test_refuses_to_resync_an_already_registered_agent_without_reinstall
    with_probe(version: "2.0.0") do |installer|
      File.write(File.join(installer.plastic_home, "VERSION"), "2.0.0")
      installer.selected = ["claude"]
      installer.registered = ["claude"]

      _output, error = capture_io { assert_equal 1, installer.cli(["--claude"]) }

      assert_includes error, "already installed"
      assert_empty installer.runs
    end
  end

  def test_resyncs_only_the_unregistered_selection_and_reports_the_other_one
    with_probe(version: "2.0.0") do |installer|
      File.write(File.join(installer.plastic_home, "VERSION"), "2.0.0")
      installer.selected = %w[claude codex]
      installer.registered = ["claude"]

      assert_equal 0, installer.cli(["--claude", "--codex", "--force"])

      assert_equal [{ selected: ["codex"], force: true, reinstall: false, ledger_action: nil,
                      argv: ["--claude", "--codex", "--force"], already_registered: ["claude"] }], installer.runs
    end
  end

  def test_checks_supported_and_missing_gems_without_using_the_real_home
    with_probe do |installer|
      assert_equal ["plastic/no_such_runtime_dependency"], installer.missing_gems(%w[json plastic/no_such_runtime_dependency])

      with_replacement(Sqlite3Dependency, :available?, -> { true }) { assert installer.send(:supported_gem?, "sqlite3") }
      refute installer.send(:supported_gem?, "plastic/no_such_runtime_dependency")
    end
  end

  private

  def with_probe(version: "2.1.0")
    Dir.mktmpdir("plastic-installer-runtime") do |home|
      installer = Probe.new(home)
      installer.instance_variable_set(:@version, version)
      yield installer
    end
  end

  def with_replacement(receiver, name, replacement)
    singleton = receiver.singleton_class
    original = receiver.method(name)
    singleton.define_method(name, &replacement)
    yield
  ensure
    singleton.define_method(name, original)
  end
end
