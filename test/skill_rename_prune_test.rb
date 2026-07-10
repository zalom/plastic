require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/lib/installer_core"

# Intent 158a (AC14): the group-first skill renames rely on the EXISTING manifest-diff
# prune in InstallerCore#install_for_agent (no new one-off migration mechanism, per the
# owner's design ruling recorded in 158a's Insights). This test proves that mechanism
# actually covers a rename: installing a package whose skills/ dir carries an OLD-name
# skill, then re-installing for the SAME agent from a package whose skills/ dir has been
# renamed (old dir gone, new dir present), deletes the stale old-name install and its
# now-empty directory.
#
# Hermetic: two throwaway package_root trees + one throwaway agent dir + one throwaway
# plastic_home, all under Dir.mktmpdir. No eval, no ENV/global seam; agents: is injected
# so install_for_agent targets our tmp agent dir instead of ~/.claude.
class SkillRenamePruneTest < Minitest::Test
  def setup
    @plastic_home = Dir.mktmpdir("skill-rename-prune-home")
    @agent_dir = Dir.mktmpdir("skill-rename-prune-agent")
    @pkg_v1 = Dir.mktmpdir("skill-rename-prune-pkg-v1")
    @pkg_v2 = Dir.mktmpdir("skill-rename-prune-pkg-v2")
  end

  def teardown
    [@plastic_home, @agent_dir, @pkg_v1, @pkg_v2].each { |d| FileUtils.rm_rf(d) }
  end

  def claude_agents(dir)
    [{ key: "claude", name: "Claude Code", dir: dir, flag: "--claude" }]
  end

  def write_skill(pkg_root, dir_name)
    skill_dir = File.join(pkg_root, "skills", dir_name)
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "---\nname: plastic-#{dir_name}\n---\nbody\n")
  end

  def test_rename_prunes_the_stale_old_name_skill_dir
    # v1 package ships the skill under its OLD name.
    write_skill(@pkg_v1, "creating-intent")
    installer_v1 = InstallerCore.new(
      package_root: @pkg_v1, plastic_home: @plastic_home, version: "1.0.0-test1",
      agents: claude_agents(@agent_dir),
    )
    result1 = installer_v1.install_for_agent("claude", false)
    assert result1[:success], "first install must succeed"

    old_skill_dir = File.join(@agent_dir, "skills", "plastic-creating-intent")
    old_skill_file = File.join(old_skill_dir, "SKILL.md")
    assert File.file?(old_skill_file), "old-name skill must be installed on the first pass"

    manifest_path_1 = File.join(@agent_dir, "plastic", "manifest.json")
    manifest_1 = JSON.parse(File.read(manifest_path_1))["files"]
    assert manifest_1.key?(old_skill_file), "manifest must track the old-name skill file"

    # v2 package ships the SAME skill under its NEW (renamed) name; the old dir does not
    # exist in this package tree at all, mirroring a real rename in the shipped repo.
    write_skill(@pkg_v2, "intent-creating")
    installer_v2 = InstallerCore.new(
      package_root: @pkg_v2, plastic_home: @plastic_home, version: "1.0.0-test2",
      agents: claude_agents(@agent_dir),
    )
    result2 = installer_v2.install_for_agent("claude", false)
    assert result2[:success], "second (renamed) install must succeed"

    new_skill_file = File.join(@agent_dir, "skills", "plastic-intent-creating", "SKILL.md")
    assert File.file?(new_skill_file), "new-name skill must be installed on the second pass"

    refute File.exist?(old_skill_file), "stale old-name skill file must be pruned"
    refute File.directory?(old_skill_dir), "now-empty old-name skill dir must be removed"

    assert result2[:pruned], "install_for_agent must report a positive prune count on rename"
    assert result2[:pruned].positive?, "prune count must be positive, got #{result2[:pruned].inspect}"

    manifest_path_2 = File.join(@agent_dir, "plastic", "manifest.json")
    manifest_2 = JSON.parse(File.read(manifest_path_2))["files"]
    assert manifest_2.key?(new_skill_file), "manifest must track the new-name skill file"
    refute manifest_2.key?(old_skill_file), "manifest must no longer track the old-name skill file"
  end
end
