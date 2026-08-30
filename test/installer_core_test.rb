require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "yaml"

require_relative "../scripts/lib/installer_core"

# Channel derivation, semver, and the append-only versions.json ledger (intent 30a1a).
class InstallerCoreTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("core-test")
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home, version: "1.0.0-alpha.18")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- channel_for ---

  def test_channel_for_alpha_beta_stable
    assert_equal "alpha", @core.channel_for("1.0.0-alpha.18")
    assert_equal "beta", @core.channel_for("1.2.0-beta.1")
    assert_equal "latest", @core.channel_for("1.2.3")
  end

  def test_stability_rank_orders_latest_above_beta_above_alpha
    assert @core.stability_rank("latest") > @core.stability_rank("beta")
    assert @core.stability_rank("beta") > @core.stability_rank("alpha")
    assert_equal @core.stability_rank("1.0.0-beta.2"), @core.stability_rank("beta")
  end

  # --- semver ---

  def test_semver_compare_precedence
    assert_equal 1, @core.semver_compare("1.0.0-alpha.18", "1.0.0-alpha.17")
    assert_equal(-1, @core.semver_compare("1.0.0-alpha.9", "1.0.0-beta.1"))
    assert_equal 1, @core.semver_compare("1.0.0", "1.0.0-beta.5") # release > prerelease
    assert_equal 0, @core.semver_compare("1.0.0", "1.0.0")
    assert_nil @core.semver_compare("not-a-version", "1.0.0")
  end

  def test_semver_gt
    assert @core.semver_gt?("1.0.0-alpha.18", "1.0.0-alpha.17")
    refute @core.semver_gt?("1.0.0-alpha.17", "1.0.0-alpha.18")
  end

  # --- ledger ---

  def test_ledger_append_is_append_only_jsonl
    @core.ledger_append("1.0.0-alpha.17", "install")
    before = File.read(@core.ledger_path)
    @core.ledger_append("1.0.0-alpha.18", "update")
    after = File.read(@core.ledger_path)

    assert after.start_with?(before), "prior ledger bytes must never be rewritten"
    assert_equal 2, after.lines.count
  end

  def test_ledger_read_and_current
    assert_empty @core.ledger_read
    @core.ledger_append("1.0.0-alpha.17", "install")
    @core.ledger_append("1.0.0-alpha.18", "update")

    entries = @core.ledger_read
    assert_equal 2, entries.length
    assert_equal({ "version" => "1.0.0-alpha.18", "action" => "update" },
                 @core.ledger_current.slice("version", "action"))
    assert_equal "install", entries.first["action"]
  end

  def test_ledger_entry_has_no_channel_field
    @core.ledger_append("1.0.0-beta.1", "update")
    entry = @core.ledger_current
    refute entry.key?("channel"), "channel is derived from version, never stored"
    assert entry.key?("at")
  end

  # --- ledger harness field (intent 210, G5) ---

  def test_ledger_append_with_harness_records_it
    @core.ledger_append("1.6.0", "update", harness: "codex")
    entry = @core.ledger_current
    assert_equal "codex", entry["harness"]
  end

  def test_ledger_append_without_harness_omits_the_key
    @core.ledger_append("1.6.0", "update")
    entry = @core.ledger_current
    refute entry.key?("harness"), "a core-only append must not invent a harness value"
  end

  def test_ledger_read_tolerates_a_legacy_row_with_no_harness_key
    File.write(@core.ledger_path, JSON.generate("version" => "1.4.1", "action" => "install", "at" => "2026-01-01T00:00:00Z") + "\n")
    entries = @core.ledger_read
    assert_equal 1, entries.length
    assert_equal "1.4.1", entries.first["version"]
    refute entries.first.key?("harness")
  end

  # --- distribute: global manifest ---

  def test_distribute_writes_global_manifest
    @core.distribute(:install)

    manifest_path = File.join(@home, "manifest.json")
    assert File.exist?(manifest_path), "distribute must write #{manifest_path}"

    data = JSON.parse(File.read(manifest_path))
    files = data["files"]
    assert_kind_of Hash, files, "manifest must have a 'files' hash"

    # VERSION file must be present and hash must match on-disk content
    version_path = File.join(@home, "VERSION")
    assert files.key?(version_path), "manifest must list VERSION (#{version_path})"
    assert_equal Digest::SHA256.file(version_path).hexdigest, files[version_path],
                 "manifest sha256 for VERSION must match on-disk digest"

    # Every core_files dest that exists must be in the manifest with correct hash
    @core.core_files.each_value do |dest|
      abs = File.join(@home, dest)
      next unless File.exist?(abs)
      assert files.key?(abs), "manifest must list #{abs}"
      assert_equal Digest::SHA256.file(abs).hexdigest, files[abs],
                   "manifest sha256 for #{abs} must match on-disk digest"
    end

    # manifest.json itself must NOT be listed
    refute files.key?(manifest_path), "manifest must not list itself"
  end

  def test_distribute_update_mode_also_writes_manifest
    @core.distribute(:update)
    assert File.exist?(File.join(@home, "manifest.json")),
           "distribute(:update) must also write the global manifest"
  end

  # Regression guard (intent 78): every scripts/lib/*.rb in the package must be listed in
  # the core_files manifest. Without this, a new lib file (e.g. power_tools.rb from 66b) can
  # be require_relative'd but never installed, raising a LoadError in the live hook.
  def test_every_lib_file_is_in_the_manifest
    manifest = @core.core_files
    lib_files = Dir[File.join(WORKTREE, "scripts/lib/*.rb")].map do |path|
      path.sub("#{WORKTREE}/", "")
    end
    refute_empty lib_files, "expected scripts/lib/*.rb files to exist in the package"
    missing = lib_files.reject { |rel| manifest.key?(rel) }
    assert_empty missing,
                 "scripts/lib files missing from InstallerCore#core_files manifest " \
                 "(they will not be installed): #{missing.join(', ')}"
  end

  # Regression guard (intent 86): every `scripts/<x>` command named in a scripts/doctor.rb
  # fix_hint must be a key in the core_files manifest, so doctor never tells a user to run a
  # tool the installer does not ship. Mirrors test_every_lib_file_is_in_the_manifest (intent 78).
  def test_every_fix_hint_script_is_in_the_manifest
    manifest = @core.core_files
    doctor_src = File.read(File.join(WORKTREE, "scripts/doctor.rb"))

    # fix_hint literals follow the convention `"Run scripts/<token> ..."`. Extract every
    # scripts/<token> mentioned in those "Run ..." string literals.
    scripts = doctor_src
      .scan(/"Run (scripts\/[A-Za-z0-9._-]+)[^"]*"/)
      .flatten
      .uniq

    refute_empty scripts,
                 "expected scripts/doctor.rb fix_hints to name at least one scripts/<x> command; " \
                 "if this is empty the guard is vacuous"

    missing = scripts.reject { |rel| manifest.key?(rel) }
    assert_empty missing,
                 "scripts/doctor.rb fix_hints name commands missing from InstallerCore#core_files " \
                 "(doctor would tell users to run an unshipped tool): #{missing.join(', ')}"
  end

  # --- agent_installed? (intent 198, D7 follow-up) ---
  #
  # Distinct from `installed?` in install.rb (a GLOBAL "is core present at
  # all" check). This is the per-agent probe install.rb's gate needed but
  # never had, which is why adding a new harness to an existing install used
  # to be refused outright. Own agents fixtures (tmpdir dirs), never the
  # shared @core built in setup.

  def test_agent_installed_false_with_no_manifest_file
    dir = Dir.mktmpdir("agent-installed-none")
    core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: [{ key: "codex", name: "Codex CLI", dir: dir, home_dir: dir, flag: "--codex" }],
                              version: "1.0.0-test")
    refute core.agent_installed?("codex"), "no manifest at all means nothing registered for this agent"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_installed_false_with_an_empty_manifest
    dir = Dir.mktmpdir("agent-installed-empty")
    FileUtils.mkdir_p(File.join(dir, "plastic"))
    File.write(File.join(dir, "plastic", "manifest.json"), JSON.generate("version" => "1", "files" => {}))
    core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: [{ key: "codex", name: "Codex CLI", dir: dir, home_dir: dir, flag: "--codex" }],
                              version: "1.0.0-test")
    refute core.agent_installed?("codex"), "a manifest with an empty files list means nothing registered"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_installed_true_once_the_manifest_tracks_a_file
    dir = Dir.mktmpdir("agent-installed-present")
    FileUtils.mkdir_p(File.join(dir, "plastic"))
    File.write(File.join(dir, "plastic", "manifest.json"),
               JSON.generate("version" => "1", "files" => { File.join(dir, "marker") => "x" }))
    core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: [{ key: "codex", name: "Codex CLI", dir: dir, home_dir: dir, flag: "--codex" }],
                              version: "1.0.0-test")
    assert core.agent_installed?("codex")
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_installed_uses_the_claude_manifest_path
    dir = Dir.mktmpdir("agent-installed-claude")
    FileUtils.mkdir_p(File.join(dir, "plastic"))
    File.write(File.join(dir, "plastic", "manifest.json"),
               JSON.generate("version" => "1", "files" => { File.join(dir, "marker") => "x" }))
    core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: [{ key: "claude", name: "Claude Code", dir: dir, flag: "--claude" }],
                              version: "1.0.0-test")
    assert core.agent_installed?("claude")
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_installed_false_for_an_unknown_key
    refute @core.agent_installed?("nope")
  end

  # --- installed_agents / agent_version_for (intent 210, D1) ---

  def test_installed_agents_reads_the_per_agent_version_file
    claude_dir = Dir.mktmpdir("installed-agents-claude")
    codex_dir = Dir.mktmpdir("installed-agents-codex")
    FileUtils.mkdir_p(File.join(claude_dir, "plastic"))
    File.write(File.join(claude_dir, "plastic", "VERSION"), "1.6.0\n")
    # codex_dir has no plastic/VERSION at all: not installed.

    core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: [
                                { key: "claude", name: "Claude Code", dir: claude_dir, flag: "--claude" },
                                { key: "codex", name: "Codex CLI", dir: codex_dir, home_dir: codex_dir, flag: "--codex" },
                              ], version: "1.0.0-test")

    assert_equal ["claude"], core.installed_agents
  ensure
    FileUtils.rm_rf(claude_dir)
    FileUtils.rm_rf(codex_dir)
  end

  # --- intent 312: the seeded config and the compact-instructions block ---

  def test_bootstrap_seeds_the_two_context_thresholds
    capture_io { @core.bootstrap }
    config = YAML.safe_load(File.read(File.join(@home, "config.yml")))

    assert_equal 350_000, config["context_offer_tokens"]
    assert_equal 500_000, config["context_insist_tokens"]
  end

  def test_install_claude_injects_the_compact_block_and_never_tracks_claude_md
    dir = Dir.mktmpdir("install-claude-compact")
    capture_io { @core.install_claude({ name: "Claude Code", dir: dir }, false, argv: ["--no-statusline"]) }

    claude_md = File.join(dir, "CLAUDE.md")
    assert File.exist?(claude_md), "install_claude must write the compact-instructions block"
    assert_includes File.read(claude_md), InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX

    manifest = JSON.parse(File.read(File.join(dir, "plastic", "manifest.json")))
    tracked = (manifest["files"] || {}).keys
    refute_includes tracked, claude_md,
      "CLAUDE.md is a partial-ownership user file: tracking it would delete it wholesale on uninstall"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_version_for_reads_the_stripped_version_string
    dir = Dir.mktmpdir("agent-version-for")
    FileUtils.mkdir_p(File.join(dir, "plastic"))
    File.write(File.join(dir, "plastic", "VERSION"), "1.5.2\n")

    assert_equal "1.5.2", @core.agent_version_for({ dir: dir })
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_version_for_nil_when_no_version_file
    dir = Dir.mktmpdir("agent-version-for-missing")
    FileUtils.mkdir_p(dir)

    assert_nil @core.agent_version_for({ dir: dir })
  ensure
    FileUtils.rm_rf(dir)
  end

  # --- read_package_version fallback (row B, spec 315b) -----------------------
  #
  # The installed rollback.rb/update.rb construct InstallerCore with
  # package_root: ~/.plastic, which carries VERSION but never package.json
  # (the installer never copies that file). Before this fallback,
  # InstallerCore.new crashed there with a raw Errno::ENOENT.

  def test_b1_reads_package_json_when_present
    dir = Dir.mktmpdir("read-package-version-b1")
    File.write(File.join(dir, "package.json"), JSON.generate("version" => "9.9.9"))

    assert_equal "9.9.9", InstallerCore.new(package_root: dir, plastic_home: @home).version
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_b2_falls_back_to_version_file_when_package_json_absent
    dir = Dir.mktmpdir("read-package-version-b2")
    File.write(File.join(dir, "VERSION"), "2.0.0-alpha.5\n")

    assert_equal "2.0.0-alpha.5", InstallerCore.new(package_root: dir, plastic_home: @home).version
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_b3_raises_a_named_error_when_neither_file_exists
    dir = Dir.mktmpdir("read-package-version-b3")

    error = assert_raises(RuntimeError) { InstallerCore.new(package_root: dir, plastic_home: @home) }
    assert_includes error.message, "package.json"
    assert_includes error.message, "VERSION"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_b4_constructor_succeeds_against_a_version_only_root
    dir = Dir.mktmpdir("read-package-version-b4")
    File.write(File.join(dir, "VERSION"), "1.14.1\n")

    core = InstallerCore.new(package_root: dir, plastic_home: @home)
    assert_equal "1.14.1", core.version
  ensure
    FileUtils.rm_rf(dir)
  end
end
