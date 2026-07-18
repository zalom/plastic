require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

require_relative "../scripts/lib/installer_core"

# Per-agent transaction with auto-restore (intent 210, D3/D4): snapshot -> apply ->
# verify -> auto-restore on failure, forward-fix (a failure never touches a sibling
# agent). Hermetic: real hermes/claude adapters run against throwaway tmpdirs, and a
# post-install corruption hook simulates the falsifiable verify failure.
class UpdateTransactionTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("txn-home")
    @claude_dir = Dir.mktmpdir("txn-claude")
    @hermes_dir = Dir.mktmpdir("txn-hermes")
    @agents = [
      { key: "claude", name: "Claude Code", dir: @claude_dir, flag: "--claude" },
      { key: "hermes", name: "Hermes", dir: @hermes_dir, flag: "--hermes" },
    ]
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home, agents: @agents, version: "1.0.0-test")
  end

  def teardown
    [@home, @claude_dir, @hermes_dir].each { |d| FileUtils.rm_rf(d) }
  end

  def test_fresh_install_verify_passes_and_records_versions
    result = @core.transactional_install_for_agent("claude", false)

    assert result[:success], "a clean fresh install must verify and succeed"
    assert_nil result[:from_version], "a fresh install has no prior version"
    assert_equal "1.0.0-test", result[:to_version]
  end

  # AC5, falsifiable: a corrupted post-install write must trigger auto-restore, and
  # ONLY for the corrupted agent. A sibling agent installed in the same run must still
  # succeed untouched (per-agent isolation, D3).
  def test_verify_failure_restores_only_the_failed_agent_sibling_still_succeeds
    # Establish a prior good install for claude, so a restore snapshot exists.
    @core.install_for_agent("claude", false)
    manifest_path = File.join(@claude_dir, "plastic", "manifest.json")
    tracked_file = JSON.parse(File.read(manifest_path))["files"].keys.first
    original_content = File.read(tracked_file)

    corrupting_core = Class.new(InstallerCore) do
      def install_for_agent(key, force, **kwargs)
        result = super
        if key == "claude"
          config = agent_config(key)
          # Corrupt the first tracked file so its hash no longer matches the manifest.
          target = manifest_files(manifest_path_for(key, config)).first
          File.write(target, "CORRUPTED\n") if target
        end
        result
      end
    end.new(package_root: WORKTREE, plastic_home: @home, agents: @agents, version: "1.0.0-test")

    claude_result = corrupting_core.transactional_install_for_agent("claude", false)
    hermes_result = corrupting_core.transactional_install_for_agent("hermes", false)

    refute claude_result[:success], "a verify failure must be reported as a failure"
    assert_match(/restored prior snapshot/, claude_result[:reason])
    assert_equal original_content, File.read(tracked_file), "restore must put the original file content back"
    assert corrupting_core.verify_agent_manifest(agent_config_for(corrupting_core, "claude")),
      "post-restore the manifest and the files it lists must agree again"

    assert hermes_result[:success], "a sibling agent installed in the same run must not be affected"
  end

  def agent_config_for(core, key)
    core.agents.find { |a| a[:key] == key }
  end

  # Fresh-install verify-failure prunes the partial write instead of restoring (no
  # prior snapshot exists to restore to).
  def test_fresh_install_verify_failure_prunes_the_partial_write
    corrupting_core = Class.new(InstallerCore) do
      def install_for_agent(key, force, **kwargs)
        result = super
        config = agent_config(key)
        target = manifest_files(manifest_path_for(key, config)).first
        File.delete(target) if target && File.exist?(target) # simulate a partial/incomplete write
        result
      end
    end.new(package_root: WORKTREE, plastic_home: @home, agents: @agents, version: "1.0.0-test")

    result = corrupting_core.transactional_install_for_agent("hermes", false)

    refute result[:success]
    assert_match(/partial install pruned/, result[:reason])
  end

  def test_idempotent_second_run_is_a_clean_noop_and_keeps_one_snapshot
    first = @core.transactional_install_for_agent("claude", false)
    assert first[:success]

    second = @core.transactional_install_for_agent("claude", false, reinstall: true)
    assert second[:success], "a clean re-run must still verify and succeed"

    snapshot_dir = @core.backup_dir_for(agent_config_for(@core, "claude"))
    snapshotted_files = Dir.glob(File.join(snapshot_dir, "**", "*")).select { |f| File.file?(f) }
    manifest_count = JSON.parse(File.read(File.join(@claude_dir, "plastic", "manifest.json")))["files"].size

    # One snapshot kept: snapshot_agent rm_rf's the dir before writing, so the count
    # reflects a single generation's worth of files, not an accumulation across runs.
    assert_equal manifest_count + 1, snapshotted_files.size, # +1 for the manifest itself
      "exactly one snapshot generation must be kept, not an accumulation across re-runs"
  end
end
