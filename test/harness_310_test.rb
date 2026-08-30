# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../scripts/lib/installer_core"

# Intent 310 packaging and install-path pins: every root-level registered file ships in the
# npm tarball, the install verb and skill carry no channel flag that never selected a package
# (removed in 2.0, intent 310), and update accepts --yes.
class Harness310Test < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def test_every_root_level_registered_file_is_in_the_npm_files_allowlist
    files = JSON.parse(File.read(File.join(REPO, "package.json")))["files"]
    core = InstallerCore.new(package_root: REPO, plastic_home: Dir.tmpdir, version: "x")
    roots = core.hand_registered_files.keys.reject { |k| k.include?("/") }
    missing = roots.reject { |k| files.include?(k) }
    assert_empty missing, "registered at the package root but not in package.json files: #{missing.inspect}"
  end

  def test_install_verb_and_skill_carry_no_dead_channel_flag
    install = File.read(File.join(REPO, "scripts", "install.rb"))
    skill = File.read(File.join(REPO, "skills", "install", "SKILL.md"))
    %w[--alpha --beta --latest].each do |flag|
      refute_includes install, flag, "install.rb still advertises #{flag} (dead since 2.0, intent 310)"
      refute_match(/\| `#{flag}` \|/, skill, "the install skill still tables #{flag}")
    end
    assert_match(/@zalom\/plastic@alpha install/, skill, "the skill names the pinned alpha install")
    refute_match(/def channel_from/, File.read(File.join(REPO, "scripts", "lib", "installer_core.rb")))
  end

  def test_update_help_names_yes
    assert_includes File.read(File.join(REPO, "scripts", "update.rb")), "--yes"
  end
end
