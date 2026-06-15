require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/lib/installer_core"

# Channel derivation, semver, and the append-only versions.json ledger (intent 30a1a).
class InstallerCoreTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("core-test")
    @core = InstallerCore.new(package_root: ".", plastic_home: @home, version: "1.0.0-alpha.18")
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
end
