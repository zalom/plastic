require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "digest"

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
    File.write(File.join(src, "_decision-tables.md"), "tables")

    skills_root = File.join(@dir, "skills")
    installed = @installer.install_skills_flat(src, skills_root)

    assert File.file?(File.join(skills_root, "plastic-doctor", "SKILL.md"))
    assert File.file?(File.join(skills_root, "plastic-auto", "SKILL.md"))
    refute File.directory?(File.join(skills_root, "plastic")), "no nested plastic/ dir"
    # gate file is relocated to PLASTIC_HOME, not the skills tree
    assert File.file?(File.join(PKG_TEST_HOME, "_active-intent-gate.md"))
    refute File.exist?(File.join(skills_root, "_active-intent-gate.md"))
    assert_includes installed, File.join(PKG_TEST_HOME, "_active-intent-gate.md")
    # any top-level underscore markdown fragment relocates the same way, not just the gate
    assert File.file?(File.join(PKG_TEST_HOME, "_decision-tables.md"))
    refute File.exist?(File.join(skills_root, "_decision-tables.md"))
    assert_includes installed, File.join(PKG_TEST_HOME, "_decision-tables.md")
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

  # Generalized guard (intent 190): globs the repo's REAL templates/ directory,
  # never a hardcoded list, and checks both layers: core_files registration and
  # distribute() actually landing every file in a fresh tmp plastic_home. This
  # must fail on any future refactor that drops a templates/* file from either
  # layer, with zero further edits to this test.
  def test_every_repo_template_is_registered_and_installed
    installer = InstallerCore.new(package_root: REPO, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")

    template_paths = Dir.glob(File.join(REPO, "templates", "*")).select { |p| File.file?(p) }
    template_names = template_paths.map { |p| File.basename(p) }
    refute_empty template_names, "expected templates/*.md files in the repo"

    # Layer 1: core_files registration (fails before the fix: only 6/13).
    unregistered = template_names.reject { |name| installer.core_files.value?(File.join("templates", name)) }
    assert_empty unregistered, "templates/* missing from core_files: #{unregistered.join(", ")}"

    # Layer 2: distribute() must actually copy every one into plastic_home.
    installer.distribute(:install)
    not_landed = template_names.reject { |name| File.exist?(File.join(PKG_TEST_HOME, "templates", name)) }
    assert_empty not_landed, "distribute() did not copy into plastic_home: #{not_landed.join(", ")}"

    # Byte-for-byte, not just present: catch a copy that silently truncates/corrupts.
    template_names.each do |name|
      expected_content = File.read(File.join(REPO, "templates", name))
      actual_content = File.read(File.join(PKG_TEST_HOME, "templates", name))
      assert_equal expected_content, actual_content, "#{name} content mismatch after distribute()"
    end
  end

  def test_templates_dir_is_packaged_for_distribution
    pkg = JSON.parse(File.read(File.join(REPO, "package.json")))
    assert_includes pkg["files"], "templates/",
      "templates/ must be in package.json `files` so it ships to consumers"
  end

  # --- Agents are synced into each harness agent dir under the manifest (intent 63) ---
  # Role files in agents/ form the auto-mode team. The installer must copy every
  # shipped agents/*.md into <dir>/agents/ and track each in the harness manifest,
  # so prune-on-update and uninstall cover them for free. These guards fail loudly
  # if install_agents is removed or a role file stops being tracked.

  def test_install_agents_copies_and_returns_every_agent
    pkg_root = File.join(@dir, "pkg")
    FileUtils.mkdir_p(File.join(pkg_root, "agents"))
    %w[plastic-planner.md plastic-enforcer.md].each do |name|
      File.write(File.join(pkg_root, "agents", name), "# #{name}")
    end
    installer = InstallerCore.new(package_root: pkg_root, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")

    agents_root = File.join(@dir, "agents")
    installed = installer.install_agents(agents_root)

    %w[plastic-planner.md plastic-enforcer.md].each do |name|
      dest = File.join(agents_root, name)
      assert File.file?(dest), "#{name} must be copied into the agent dir"
      assert_includes installed, dest, "returned paths must include #{name}"
    end
  end

  def test_install_agents_is_noop_without_an_agents_dir
    pkg_root = File.join(@dir, "pkg-noagents")
    FileUtils.mkdir_p(pkg_root)
    installer = InstallerCore.new(package_root: pkg_root, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")

    assert_empty installer.install_agents(File.join(@dir, "agents"))
  end

  # claude/hermes: install_agents copies agents/*.md verbatim into <dir>/agents,
  # manifest-tracked there. codex is covered separately below: generate_codex_agents
  # renders each agents/*.md into a standalone <home_dir>/agents/<basename>.toml
  # (intent 102a); the flat .md copy is dead on codex and must NOT be written.
  def test_every_repo_agent_installs_and_is_manifest_tracked_for_each_harness
    agent_names = Dir.glob(File.join(REPO, "agents", "*.md")).map { |p| File.basename(p) }
    refute_empty agent_names, "expected agents/*.md role files to ship"

    installer = InstallerCore.new(package_root: REPO, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")

    harnesses = [
      ["claude", ->(dir) { installer.install_claude({ name: "Claude Code", dir: dir }, false) },
       ->(dir) { File.join(dir, "plastic", "manifest.json") }],
      ["hermes", ->(dir) { installer.install_hermes({ name: "Hermes", dir: dir }, false) },
       ->(dir) { File.join(dir, "plastic-manifest.json") }],
    ]

    harnesses.each do |key, run_install, manifest_for|
      agent_home = File.join(@dir, key)
      FileUtils.mkdir_p(agent_home)
      run_install.call(agent_home)

      agents_root = File.join(agent_home, "agents")
      manifest = JSON.parse(File.read(manifest_for.call(agent_home)))["files"]

      agent_names.each do |name|
        dest = File.join(agents_root, name)
        assert File.file?(dest), "#{key}: #{name} must install into #{agents_root}"
        assert manifest.key?(dest), "#{key}: manifest must track #{dest}"
        assert_equal Digest::SHA256.file(dest).hexdigest, manifest[dest],
          "#{key}: manifest sha256 for #{name} must match on-disk digest"
      end
    end
  end

  def test_every_repo_agent_generates_a_codex_toml_and_is_manifest_tracked
    agent_basenames = Dir.glob(File.join(REPO, "agents", "*.md")).map { |p| File.basename(p, ".md") }
    refute_empty agent_basenames, "expected agents/*.md role files to ship"

    installer = InstallerCore.new(package_root: REPO, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")

    codex_dir = File.join(@dir, "codex")
    home_dir = File.join(@dir, "codex-home")
    FileUtils.mkdir_p(codex_dir)
    installer.install_codex({ name: "Codex CLI", dir: codex_dir, home_dir: home_dir }, false)

    agents_root = File.join(home_dir, "agents")
    manifest = JSON.parse(File.read(File.join(codex_dir, "plastic-manifest.json")))["files"]

    # Codex has no fable alias: consultation agents (intent 185) are excluded from
    # generation, checked separately below.
    codex_expected = agent_basenames - AgentModels::CONSULTATION_AGENTS

    codex_expected.each do |basename|
      dest = File.join(agents_root, "#{basename}.toml")
      assert File.file?(dest), "codex: #{basename}.toml must be generated into #{agents_root}"
      assert manifest.key?(dest), "codex: manifest must track #{dest}"
      assert_equal Digest::SHA256.file(dest).hexdigest, manifest[dest],
        "codex: manifest sha256 for #{basename}.toml must match on-disk digest"
    end

    assert_empty Dir.glob(File.join(codex_dir, "agents", "*.md")),
      "codex: the dead ~/.agents/agents/*.md copy must not be written"
  end

  def test_generate_codex_agents_skips_consultation_agents_by_name
    installer = InstallerCore.new(package_root: REPO, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")
    agents_root = File.join(@dir, "codex-agents")

    installed = installer.generate_codex_agents(agents_root)

    AgentModels::CONSULTATION_AGENTS.each do |basename|
      dest = File.join(agents_root, "#{basename}.toml")
      refute File.exist?(dest), "codex: #{basename}.toml must not be generated (no Codex advisor this release, intent 186)"
      refute_includes installed, dest
    end
  end

  # Regression guard: the Codex skip is unconditional and name-based
  # (AgentModels::CONSULTATION_AGENTS), never a peek at the authored or
  # overridden model value, so a models: override that flips an advisor's
  # model must NOT accidentally un-skip it. There is no Codex advisor path,
  # full stop.
  def test_generate_codex_agents_skip_survives_a_model_override
    installer = InstallerCore.new(package_root: REPO, plastic_home: PKG_TEST_HOME, version: "1.0.0-test")
    agents_root = File.join(@dir, "codex-agents-override")

    overrides = AgentModels::CONSULTATION_AGENTS.to_h { |basename| [basename, "opus"] }
    installed = installer.generate_codex_agents(agents_root, models: overrides)

    AgentModels::CONSULTATION_AGENTS.each do |basename|
      dest = File.join(agents_root, "#{basename}.toml")
      refute File.exist?(dest), "codex: #{basename}.toml must stay skipped even under a models: override"
      refute_includes installed, dest
    end
  end

  def test_agents_dir_is_packaged_for_distribution
    pkg = JSON.parse(File.read(File.join(REPO, "package.json")))
    assert_includes pkg["files"], "agents/",
      "agents/ must be in package.json `files` so role files ship to consumers"
  end

  def test_skills_dir_is_packaged_for_distribution
    pkg = JSON.parse(File.read(File.join(REPO, "package.json")))
    assert_includes pkg["files"], "skills/",
      "skills/ must be in package.json `files` so the agent-advisor skill and its references ship to consumers"
  end

  # --- The advisor agents and the shipped Advisor Protocol reference ship with
  # no injection surface (intent 185 final design): the faux advisor inlines
  # the Operating Manual in its own body, and the Advisor Protocol ships as a
  # skill reference. These guards fail loudly if either moves or disappears.

  def test_advisor_agent_files_exist_in_repo
    %w[plastic-advisor.md plastic-faux-advisor.md].each do |name|
      assert File.file?(File.join(REPO, "agents", name)), "agents/#{name} must exist in the repo"
    end
  end

  def test_faux_advisor_inlines_the_operating_manual
    body = File.read(File.join(REPO, "agents", "plastic-faux-advisor.md"))
    assert_includes body, "# The Operating Manual",
      "plastic-faux-advisor.md must inline the full Operating Manual in its own body"
    assert_includes body, "The five-question self-test"
  end

  def test_advisor_protocol_reference_exists_in_repo
    assert File.file?(File.join(REPO, "skills", "agent-advisor", "references", "advisor-protocol.md")),
      "skills/agent-advisor/references/advisor-protocol.md must exist in the repo"
  end
end
