# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../scripts/install"

class InstallTest < Minitest::Test
  class Probe < Install
    attr_accessor :gate, :selected, :registered, :runs

    def initialize(home, version)
      super(package_root: File.expand_path("..", __dir__), plastic_home: home, version:)
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

  def test_lists_the_gems_that_do_not_load_without_using_the_real_home
    with_probe do |installer|
      assert_equal ["plastic/no_such_runtime_dependency"], installer.missing_gems(%w[json plastic/no_such_runtime_dependency])
    end
  end

  def test_the_closing_line_names_something_the_release_ships
    with_probe do |installer|
      out, = capture_io { installer.send(:print_results, [{ agent: "Claude Code", success: true, files: 3 }], :install) }

      assert_includes shipped_names(installer), out[/Next: (?:read|run plastic help) (\S+)/, 1]
    end
  end

  def test_a_codex_install_names_the_changed_hooks_to_trust_in_codex
    with_probe do |installer|
      out, = capture_io { installer.send(:print_results, [{ agent: "Codex CLI", success: true, changed_hooks: ["hook start", "hook stop"] }], :install) }

      assert_includes out, "run /hooks, and trust the changed Plastic hooks: hook start, hook stop."
    end
  end

  def test_a_codex_install_that_changed_no_hook_asks_for_no_trust
    with_probe do |installer|
      out, = capture_io { installer.send(:print_results, [{ agent: "Codex CLI", success: true, changed_hooks: [] }], :install) }

      refute_includes out, "/hooks"
    end
  end

  class Runner < Install
    def distribute(mode) = super(mode, tmp_dirs: [])
  end

  def test_a_run_moves_a_flat_config_into_the_sections
    Dir.mktmpdir("plastic-installer-run") do |home|
      File.write(File.join(home, "config.yml"), "version: 3\nagent:\n  type: claude-code\nscreens: false\n")
      capture_io { Runner.new(package_root: File.expand_path("..", __dir__), plastic_home: home, version: "2.1.0").run(selected: [], argv: []) }

      assert_equal({ "version" => 3, "global" => { "screens" => false } }, YAML.safe_load_file(File.join(home, "config.yml")))
    end
  end

  private

  def shipped_names(installer)
    topics = installer.help_files.keys.map { |path| File.basename(path, ".md") }
    topics + installer.core_files.values
  end

  def with_probe(version: "2.1.0")
    Dir.mktmpdir("plastic-installer-runtime") do |home|
      yield Probe.new(home, version)
    end
  end
end
