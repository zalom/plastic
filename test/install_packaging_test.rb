require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

# Intent 29: Plastic ships as flat, hyphen-namespaced personal skills
# (plastic-<name>/) with NO Claude Code plugin/marketplace registration, a
# manifest-driven update that prunes removed files, and migration that removes
# any legacy plugin layout.

require_relative "../scripts/lib/installer_core"

PKG_TEST_HOME = File.join(Dir.tmpdir, "plastic-pkg-home-#{Process.pid}")

class InstallPackagingTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("pkg-test")
    @installer = InstallerCore.new(
      package_root: "/tmp/plastic-test-pkg",
      plastic_home: PKG_TEST_HOME,
      version: "1.0.0-test",
    )
    FileUtils.rm_rf(PKG_TEST_HOME)
    FileUtils.mkdir_p(PKG_TEST_HOME)
  end

  def teardown
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(PKG_TEST_HOME)
  end

  # --- No plugin registration ---

  def test_merge_hooks_does_not_register_plugin
    settings_path = File.join(@dir, "settings.json")
    File.write(settings_path, "{}")
    @installer.merge_claude_hooks(settings_path)
    settings = JSON.parse(File.read(settings_path))

    assert_nil settings["enabledPlugins"], "must not write enabledPlugins"
    assert_nil settings["extraKnownMarketplaces"], "must not write a marketplace source"
  end

  # --- Flat hyphen skill layout + gate relocation ---

  def test_install_skills_flat_produces_hyphen_dirs
    src = File.join(@dir, "skills-src")
    FileUtils.mkdir_p(File.join(src, "doctor"))
    FileUtils.mkdir_p(File.join(src, "auto"))
    File.write(File.join(src, "doctor", "SKILL.md"), "doc")
    File.write(File.join(src, "auto", "SKILL.md"), "auto")
    File.write(File.join(src, "_active-intent-gate.md"), "gate")

    skills_root = File.join(@dir, "skills")
    installed = @installer.install_skills_flat(src, skills_root)

    assert File.file?(File.join(skills_root, "plastic-doctor", "SKILL.md"))
    assert File.file?(File.join(skills_root, "plastic-auto", "SKILL.md"))
    refute File.directory?(File.join(skills_root, "plastic")), "no nested plastic/ dir"
    # gate file is relocated to PLASTIC_HOME, not the skills tree
    assert File.file?(File.join(PKG_TEST_HOME, "_active-intent-gate.md"))
    refute File.exist?(File.join(skills_root, "_active-intent-gate.md"))
    assert_includes installed, File.join(PKG_TEST_HOME, "_active-intent-gate.md")
  end

  # --- Manifest-diff prune ---

  def test_prune_removed_files_deletes_stale_and_empty_dirs
    skill_dir = File.join(@dir, "skills", "plastic-obsolete")
    FileUtils.mkdir_p(skill_dir)
    stale = File.join(skill_dir, "SKILL.md")
    File.write(stale, "x")

    removed = @installer.prune_removed_files([stale])

    assert_equal 1, removed
    refute File.exist?(stale)
    refute File.directory?(skill_dir), "now-empty skill dir should be removed"
  end

  # --- Legacy plugin migration ---

  def test_migrate_legacy_plugin_removes_all_artifacts
    claude = File.join(@dir, ".claude")
    FileUtils.mkdir_p(File.join(claude, "plugins", "marketplaces", "plastic", ".claude-plugin"))
    FileUtils.mkdir_p(File.join(claude, "plugins", "cache", "plastic", "plastic", "1.0.0-alpha.10"))
    FileUtils.mkdir_p(File.join(claude, "skills", "plastic", "auto"))

    settings_path = File.join(claude, "settings.json")
    File.write(settings_path, JSON.generate({
      "enabledPlugins" => { "plastic@plastic" => true, "other@x" => true },
      "extraKnownMarketplaces" => { "plastic" => { "source" => "x" }, "keep" => { "source" => "y" } },
    }))

    known_path = File.join(claude, "plugins", "known_marketplaces.json")
    File.write(known_path, JSON.generate({ "plastic" => { "source" => "z" }, "keep" => { "source" => "w" } }))

    removed = @installer.migrate_legacy_plugin(claude)

    refute File.directory?(File.join(claude, "plugins", "marketplaces", "plastic"))
    refute File.directory?(File.join(claude, "plugins", "cache", "plastic"))
    refute File.directory?(File.join(claude, "skills", "plastic"))

    settings = JSON.parse(File.read(settings_path))
    refute settings["enabledPlugins"].key?("plastic@plastic")
    assert settings["enabledPlugins"].key?("other@x"), "must not touch other plugins"
    refute settings["extraKnownMarketplaces"].key?("plastic")
    assert settings["extraKnownMarketplaces"].key?("keep"), "must not touch other marketplaces"

    known = JSON.parse(File.read(known_path))
    refute known.key?("plastic")
    assert known.key?("keep")

    refute_empty removed
  end

  def test_migrate_legacy_plugin_noop_when_clean
    claude = File.join(@dir, ".claude")
    FileUtils.mkdir_p(claude)
    File.write(File.join(claude, "settings.json"), "{}")
    assert_empty @installer.migrate_legacy_plugin(claude)
  end

  # --- Templates are distributed via the templates/ directory (npm `files`) ---
  # Templates ship by directory inclusion: package.json lists "templates/" and the
  # whole dir is read from ${CLAUDE_PLUGIN_ROOT}/templates/. These guards fail loudly
  # if a canonical FORM is dropped from the repo or the dir stops being packaged.

  REPO = File.expand_path("../../", __FILE__)

  def test_canonical_templates_exist_in_repo
    expected = %w[intent.md plan.md checklist.md savepoint.md index.md spec.md outcome.md]
    missing = expected.reject { |t| File.file?(File.join(REPO, "templates", t)) }
    assert_empty missing, "canonical templates missing from templates/: #{missing.join(", ")}"
  end

  def test_templates_dir_is_packaged_for_distribution
    pkg = JSON.parse(File.read(File.join(REPO, "package.json")))
    assert_includes pkg["files"], "templates/",
      "templates/ must be in package.json `files` so it ships to consumers"
  end
end
