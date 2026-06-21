require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

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
end
