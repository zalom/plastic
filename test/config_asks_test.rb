require "minitest/autorun"
require "tmpdir"
require "yaml"
require "fileutils"

require_relative "../scripts/lib/config_asks"

# ConfigAsks (intent 194): a shipped, declarative manifest so a release can
# announce a new config question without editing update.rb, doctor.rb, or any
# skill. See config_asks.yml's schema comment for the pending predicate.
class ConfigAsksTest < Minitest::Test
  REPO_ROOT = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("config-asks-test")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_manifest(entries)
    File.write(File.join(@home, "config_asks.yml"), YAML.dump("config_asks" => entries))
  end

  def write_config(data)
    File.write(File.join(@home, "config.yml"), YAML.dump(data))
  end

  def sample_entry(id: "advisor-default", key: "advisor.claude.default", introduced: "1.3.0")
    {
      "id" => id,
      "key" => key,
      "introduced" => introduced,
      "question" => "Which advisor should be the default?",
      "options" => [
        { "label" => "Faux Fable", "value" => "plastic-faux-advisor" },
        { "label" => "Fable 5", "value" => "plastic-advisor" },
      ],
    }
  end

  def test_pending_when_key_unset_and_not_dismissed
    write_manifest([sample_entry])
    # No config.yml at all -- key is unset.

    pending = ConfigAsks.pending(@home)

    assert_equal 1, pending.size
    assert_equal "advisor-default", pending.first["id"]
  end

  def test_not_pending_when_key_is_set
    write_manifest([sample_entry])
    write_config("advisor" => { "claude" => { "default" => "plastic-advisor" } })

    assert_equal [], ConfigAsks.pending(@home)
  end

  def test_not_pending_when_dismissed
    write_manifest([sample_entry])
    write_config("config_asks_dismissed" => ["advisor-default"])

    assert_equal [], ConfigAsks.pending(@home)
  end

  def test_missing_manifest_returns_empty
    # No config_asks.yml written at all.
    assert_equal [], ConfigAsks.load_entries(@home)
    assert_equal [], ConfigAsks.pending(@home)
  end

  def test_malformed_manifest_returns_empty
    File.write(File.join(@home, "config_asks.yml"), "config_asks: not_an_array\n")
    assert_equal [], ConfigAsks.load_entries(@home)

    File.write(File.join(@home, "config_asks.yml"), "not: valid: yaml: [")
    assert_equal [], ConfigAsks.load_entries(@home)
  end

  def test_write_config_command_and_dismiss_command_shape
    cmd = ConfigAsks.write_config_command(@home, "advisor.claude.default", "plastic-faux-advisor")
    assert_equal "ruby #{@home}/scripts/write-config advisor.claude.default plastic-faux-advisor", cmd

    dismiss = ConfigAsks.dismiss_command(@home, "advisor-default")
    assert_equal "ruby #{@home}/scripts/write-config config_asks_dismissed --push advisor-default", dismiss
  end

  # --- Retro-fire + no-nagging (intent 194, orchestrator amendment 2) ---
  #
  # The Problem this intent opened against said advisor.claude.default "is
  # still unset today". That premise changed mid-flight: the key was set
  # out-of-band on the owner's real ~/.plastic/config.yml on 2026-07-13,
  # after being unset for the whole 1.3.0 lifetime with the owner never
  # actually asked. The mechanism itself is unchanged either way: the pending
  # predicate ignores "introduced" entirely, so any entry -- including one
  # much older than the version currently installed -- still fires the
  # moment its key is unset. These two tests prove both halves: retro-fire
  # still works in general, and the shipped advisor-default entry correctly
  # stays silent on the owner's actual (now-set) state -- the no-nagging
  # guarantee working as designed, not a regression.

  def test_pending_ignores_introduced_even_when_far_older_than_installed_version
    # "introduced" is far older than the installed VERSION; the predicate
    # never reads VERSION at all, so this must still fire.
    write_manifest([sample_entry(id: "ancient-question", key: "some.old.key", introduced: "0.1.0")])
    File.write(File.join(@home, "VERSION"), "9.9.9")

    pending = ConfigAsks.pending(@home)

    assert_equal 1, pending.size
    assert_equal "ancient-question", pending.first["id"]
  end

  def test_shipped_advisor_default_entry_does_not_fire_when_key_is_set
    # Use the REAL, shipped config_asks.yml (not a synthetic fixture) so this
    # is a direct regression guard for the owner's actual production state.
    FileUtils.cp(File.join(REPO_ROOT, "config_asks.yml"), File.join(@home, "config_asks.yml"))
    write_config("advisor" => { "claude" => { "default" => "plastic-faux-advisor" } })

    pending = ConfigAsks.pending(@home)

    assert_empty pending,
      "advisor-default must stay silent once advisor.claude.default is set -- " \
      "the no-nagging guarantee, not a failure"
    refute pending.any? { |e| e["id"] == "advisor-default" }
  end

  # --- manifest_error: distinguish "nothing declared" from "declared but
  # broken" (fix round: an unreadable manifest must never look like a clean
  # pass to a caller) ---

  def test_manifest_error_nil_when_absent
    # No config_asks.yml at all -- a legitimate quiet no-op, not an error.
    assert_nil ConfigAsks.manifest_error(@home)
  end

  def test_manifest_error_nil_when_valid
    write_manifest([sample_entry])
    assert_nil ConfigAsks.manifest_error(@home)
  end

  def test_manifest_error_present_when_yaml_is_malformed
    File.write(File.join(@home, "config_asks.yml"), "not: valid: yaml: [")

    error = ConfigAsks.manifest_error(@home)

    refute_nil error
    assert_match(/config_asks\.yml/, error)
  end

  def test_manifest_error_present_when_top_level_is_not_an_array
    File.write(File.join(@home, "config_asks.yml"), "config_asks: not_an_array\n")

    error = ConfigAsks.manifest_error(@home)

    refute_nil error
    assert_match(/config_asks\.yml/, error)
  end

  def test_manifest_error_does_not_flag_a_broken_config_yml
    # manifest_error is scoped to config_asks.yml only; a broken config.yml is
    # a separate concern (load_config already degrades that to {} safely,
    # since ConfigAsks only reads config.yml, never writes it).
    write_manifest([sample_entry])
    File.write(File.join(@home, "config.yml"), "not: valid: yaml: [")

    assert_nil ConfigAsks.manifest_error(@home)
  end

  # --- agent scoping (fix round: the agents: field was declared but never
  # read, so an agent-scoped entry could not actually be agent-scoped) ---

  def test_pending_filters_out_entry_scoped_to_a_different_agent
    entry = sample_entry.merge("agents" => ["codex"])
    write_manifest([entry])

    assert_equal [], ConfigAsks.pending(@home, "claude")
    assert_equal 1, ConfigAsks.pending(@home, "codex").size
  end

  def test_pending_entry_without_agents_field_applies_to_every_agent
    entry = sample_entry.dup
    entry.delete("agents")
    write_manifest([entry])

    assert_equal 1, ConfigAsks.pending(@home, "claude").size
    assert_equal 1, ConfigAsks.pending(@home, "codex").size
    assert_equal 1, ConfigAsks.pending(@home, "hermes").size
  end

  def test_pending_with_nil_agent_key_does_not_filter
    entry = sample_entry.merge("agents" => ["codex"])
    write_manifest([entry])

    # No agent_key passed at all -- backward-compatible "do not filter" mode.
    assert_equal 1, ConfigAsks.pending(@home).size
  end
end
