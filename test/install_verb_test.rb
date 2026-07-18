require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/install"

# install verb orchestration: fresh vs refuse vs --reinstall, and ledger action (intent 30a1a).
# File-sync internals (distribute/install_for_agent/transactional_install_for_agent) are
# covered by installer_core / install_packaging / update_transaction tests; here we stub
# the transaction wrapper (the actual call site inside #run since intent 210, D3) to
# isolate the verb's decision logic.
class InstallVerbTest < Minitest::Test
  class FakeInstall < Install
    attr_reader :distributed, :bootstrapped
    def distribute(mode) = (@distributed = mode)
    def bootstrap = (@bootstrapped = true)
    def transactional_install_for_agent(key, _force, **)
      { agent: key, success: true, files: 1, from_version: nil, to_version: version }
    end
  end

  def setup
    @home = Dir.mktmpdir("install-verb")
    @agent_dir = Dir.mktmpdir("install-verb-agent") # ~/.claude equivalent, never the real one
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@agent_dir)
  end

  def build
    FakeInstall.new(package_root: ".", plastic_home: @home, version: "1.0.0-alpha.18",
                     agents: [{ key: "claude", name: "Claude Code", dir: @agent_dir, flag: "--claude" }])
  end

  def mark_installed(v = "1.0.0-alpha.18")
    File.write(File.join(@home, "VERSION"), "#{v}\n")
  end

  # Per-agent registration fixture (intent 198, D7 follow-up): a manifest with
  # at least one tracked file is the signal InstallerCore#agent_installed?
  # reads. Written at the real per-agent path (dir/plastic/manifest.json for
  # claude) so these tests stay hermetic instead of depending on whatever the
  # machine running them happens to have installed for real under ~/.claude.
  def register_claude(dir)
    manifest_dir = File.join(dir, "plastic")
    FileUtils.mkdir_p(manifest_dir)
    File.write(File.join(manifest_dir, "manifest.json"),
               JSON.generate("version" => "1", "files" => { File.join(dir, "marker") => "x" }))
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
    register_claude(@agent_dir) # claude is already registered too, the case this gate was written for
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

# Per-agent registration gate (intent 198, D7): the owner ran `install --codex`
# on a machine where Plastic v1.4.0 was already installed for Claude, but Codex
# had zero Plastic files (no manifest, no ~/.agents, no ~/.codex/hooks.json, no
# ~/.codex/AGENTS.md). The old gate asked only "is Plastic core installed at
# all" and refused, installing nothing for Codex. These tests drive the REAL
# Install/InstallerCore file-writing path (never a Fake stub), so a false
# green from stubbing out the exact code path that broke cannot happen again.
class InstallPerAgentGateTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("install-gate-home")            # plastic_home
    @claude_dir = Dir.mktmpdir("install-gate-claude")     # ~/.claude equivalent
    @agent_dir = Dir.mktmpdir("install-gate-agents")      # ~/.agents equivalent (codex's shared skills root)
    @codex_home = Dir.mktmpdir("install-gate-codex-home") # ~/.codex equivalent, pre-created per D1 convention
    @agents = [
      { key: "claude", name: "Claude Code", dir: @claude_dir, flag: "--claude" },
      { key: "codex", name: "Codex CLI", dir: @agent_dir, home_dir: @codex_home, flag: "--codex" },
    ]
  end

  def teardown
    [@home, @claude_dir, @agent_dir, @codex_home].each { |d| FileUtils.rm_rf(d) }
  end

  def build(agents = @agents)
    Install.new(package_root: WORKTREE, plastic_home: @home, agents: agents, version: "1.0.0-test")
  end

  # Simulates the owner's exact starting state, via the real install path (not
  # a stub): core installed, claude fully registered, codex completely
  # untouched, matching a genuine prior `install --claude` on this machine.
  def install_claude_only(i)
    i.distribute(:install)
    i.install_for_agent("claude", false)
  end

  def test_adding_a_new_harness_to_an_existing_install_proceeds_and_writes_it
    i = build
    install_claude_only(i)

    status = nil
    out, _err = capture_io { status = i.cli(["--codex"]) }

    assert_equal 0, status,
      "adding a harness Plastic has never registered must proceed, not refuse (the D7 regression)"
    refute_empty Dir.glob(File.join(@agent_dir, "skills", "plastic-*")), "codex skills must actually be written"
    refute_empty Dir.glob(File.join(@codex_home, "agents", "plastic-*.toml")), "codex agent TOMLs must be generated"
    assert File.exist?(File.join(@codex_home, "hooks.json"))
    assert File.exist?(File.join(@codex_home, "AGENTS.md"))
    assert_includes out, "/hooks", "the Codex hooks-trust reminder must still print on this path"
    assert_includes out, "trust"
  end

  def test_reinstalling_an_already_registered_agent_alone_is_still_refused
    i = build
    install_claude_only(i)

    status = nil
    _out, err = capture_io { status = i.cli(["--claude"]) }

    assert_equal 1, status, "no behaviour change for the case this gate was written for"
    assert_match(/already installed/i, err)
  end

  def test_install_all_installs_only_the_new_harnesses_and_reports_the_rest
    hermes_dir = Dir.mktmpdir("install-gate-hermes")
    begin
      agents = @agents + [{ key: "hermes", name: "Hermes", dir: hermes_dir, flag: "--hermes" }]
      i = build(agents)
      install_claude_only(i)
      manifest_path = File.join(@claude_dir, "plastic", "manifest.json")
      before = File.mtime(manifest_path)

      status = nil
      out, _err = capture_io { status = i.cli(["--all"]) }

      assert_equal 0, status
      refute_empty Dir.glob(File.join(@agent_dir, "skills", "plastic-*")), "codex must be freshly installed"
      refute_empty Dir.glob(File.join(hermes_dir, "skills", "plastic-*")), "hermes must be freshly installed"
      assert_equal before, File.mtime(manifest_path), "claude must not be re-synced when already registered"
      assert_match(/Claude Code.*already registered/i, out)
      refute_match(/Registered for:.*Claude Code/, out,
        "claude was not installed THIS run, so it must not appear in the fresh-install summary")

      # Per-agent transaction summary table (intent 210, D3).
      assert_match(/Codex CLI\s+- \u{2192} 1\.0\.0-test\s+ok/, out)
      assert_match(/Hermes\s+- \u{2192} 1\.0\.0-test\s+ok/, out)
      assert_match(/Claude Code\s+.*skipped/, out)
    ensure
      FileUtils.rm_rf(hermes_dir)
    end
  end
end
