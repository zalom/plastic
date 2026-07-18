require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/install"

# D2 (intent 198): a successful Codex install prints the /hooks trust step,
# because Codex hooks are installed inert until a human reviews and trusts
# them. A Claude-only or Hermes-only install must never see this line.
class InstallCodexHookTrustTest < Minitest::Test
  class FakeInstall < Install
    def distribute(mode) = nil
    def bootstrap = nil

    # Mirrors the REAL install_for_agent's contract (result[:agent] =
    # config[:name]), not just the raw key, so the codex-detection logic in
    # print_codex_hook_trust_reminder (which matches on agent DISPLAY name)
    # is exercised faithfully.
    def install_for_agent(key, _force, **)
      { agent: agent_config(key)[:name], success: true, files: 1 }
    end
  end

  def setup
    @home = Dir.mktmpdir("install-codex-trust")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def build
    FakeInstall.new(package_root: ".", plastic_home: @home, version: "1.0.0-test")
  end

  def test_codex_install_prints_the_hooks_trust_step
    i = build
    out, _err = capture_io { i.run(selected: ["codex"]) }
    assert_includes out, "/hooks"
    assert_includes out, "trust"
  end

  def test_claude_only_install_does_not_print_the_hooks_trust_step
    i = build
    out, _err = capture_io { i.run(selected: ["claude"]) }
    refute_includes out, "/hooks"
  end

  def test_hermes_only_install_does_not_print_the_hooks_trust_step
    i = build
    out, _err = capture_io { i.run(selected: ["hermes"]) }
    refute_includes out, "/hooks"
  end
end
