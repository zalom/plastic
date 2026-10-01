require "minitest/autorun"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"
require "open3"
require_relative "../scripts/lib/read_config"

class ReadConfigTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/read-config", __FILE__)

  def setup
    @global_dir = Dir.mktmpdir("plastic-global")
    @project_dir = Dir.mktmpdir("plastic-project")
    @project_store = File.join(@project_dir, ".plastic_store")
    FileUtils.mkdir_p(@project_store)
  end

  def teardown
    FileUtils.rm_rf(@global_dir)
    FileUtils.rm_rf(@project_dir)
  end

  def run_script(key, default: nil, global_dir: @global_dir, project_dir: nil, harness: nil)
    env = { "PLASTIC_HOME" => global_dir }
    args = [SCRIPT, key]
    args += ["--default", default] if default
    args += ["--project", project_dir] if project_dir
    args += ["--harness", harness] if harness
    stdout, stderr, status = Open3.capture3(env, *args)
    [stdout.strip, stderr.strip, status]
  end


  def test_harness_selects_model_namespace
    write_global_config(
      "agents" => {
        "models" => {
          "claude" => { "plastic-executor" => "haiku" },
          "codex" => { "plastic-executor" => "gpt-6-astra" }
        },
        "efforts" => {
          "claude" => { "plastic-executor" => "low" },
          "codex" => { "plastic-executor" => "high" }
        }
      }
    )

    assert_equal "haiku", run_script("agents.models.plastic-executor", harness: "claude").first
    assert_equal "gpt-6-astra", run_script("agents.models.plastic-executor", harness: "codex").first
    assert_equal "low", run_script("agents.efforts.plastic-executor", harness: "claude").first
    assert_equal "high", run_script("agents.efforts.plastic-executor", harness: "codex").first
  end

  def test_harness_defaults_translate_codex_models_and_use_medium_effort
    assert_equal "sonnet", run_script("agents.models.plastic-executor", harness: "claude").first
    assert_equal "gpt-5.6-terra", run_script("agents.models.plastic-executor", harness: "codex").first
    assert_equal "medium", run_script("agents.efforts.plastic-executor", harness: "claude").first
    assert_equal "medium", run_script("agents.efforts.plastic-executor", harness: "codex").first
  end

  def write_global_config(data)
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(data))
  end

  def write_project_config(data)
    File.write(File.join(@project_store, "config.yml"), YAML.dump(data))
  end

  # Intent 312: the two absolute-token compaction thresholds resolve from DEFAULTS
  # with no config file present, and a config value wins over them.
  def test_context_defaults
    out, _, status = run_script("context_offer_tokens")
    assert status.success?
    assert_equal "150000", out

    out, _, status = run_script("context_insist_tokens")
    assert status.success?
    assert_equal "250000", out
  end

  def test_a_configured_context_threshold_wins_over_the_default
    write_global_config("version" => 3, "context_offer_tokens" => 120_000,
                        "context_insist_tokens" => 180_000)
    assert_equal "120000", run_script("context_offer_tokens").first
    assert_equal "180000", run_script("context_insist_tokens").first
  end

  def test_reads_top_level_key_from_global
    write_global_config("version" => 3, "stale_threshold_days" => 5)
    out, _, status = run_script("stale_threshold_days")
    assert status.success?
    assert_equal "5", out
  end

  def test_reads_nested_key_from_global
    write_global_config("version" => 3, "agent" => { "type" => "claude-code" })
    out, _, status = run_script("agent.type")
    assert status.success?
    assert_equal "claude-code", out
  end

  def test_returns_builtin_default_when_key_missing
    write_global_config("version" => 3)
    out, _, status = run_script("stale_threshold_days")
    assert status.success?
    assert_equal "3", out
  end

  def test_returns_explicit_default_over_builtin
    write_global_config("version" => 3)
    out, _, status = run_script("nonexistent.key", default: "fallback")
    assert status.success?
    assert_equal "fallback", out
  end

  def test_project_config_overrides_global
    write_global_config("version" => 3, "agent" => { "type" => "claude-code" })
    write_project_config("agent" => { "type" => "hermes" })
    out, _, status = run_script("agent.type", project_dir: @project_dir)
    assert status.success?
    assert_equal "hermes", out
  end

  def test_falls_through_to_global_when_project_missing_key
    write_global_config("version" => 3, "stale_threshold_days" => 7)
    write_project_config("agent" => { "type" => "hermes" })
    out, _, status = run_script("stale_threshold_days", project_dir: @project_dir)
    assert status.success?
    assert_equal "7", out
  end

  def test_no_config_files_returns_builtin_default
    Dir.mktmpdir("plastic-empty") do |empty_dir|
      out, _, status = run_script("stale_threshold_days", global_dir: empty_dir)
      assert status.success?
      assert_equal "3", out
    end
  end

  def test_json_output_for_hash_values
    write_global_config("version" => 3, "agent" => { "type" => "claude-code", "parallel_mode" => "linear" })
    out, _, status = run_script("agent")
    assert status.success?
    parsed = JSON.parse(out)
    assert_equal "claude-code", parsed["type"]
    assert_equal "linear", parsed["parallel_mode"]
  end

  def test_exits_with_error_when_no_key_given
    _, _, status = run_script("")
    refute status.success?
  end

  # Intent 340b (G7c, n4, D9, row 4.6): runner.stop_hook defaults false with
  # no config file present, so StopGate has something to parse and doctor
  # has something to report, even on a fresh install.
  def test_runner_stop_hook_defaults_false
    out, _, status = run_script("runner.stop_hook")
    assert status.success?
    assert_equal "false", out
  end

  def test_a_configured_runner_stop_hook_wins_over_the_default
    write_global_config("version" => 3, "runner" => { "stop_hook" => true })
    assert_equal "true", run_script("runner.stop_hook").first
  end
end

# Drives ReadConfig's public methods directly, in process, the same lookups
# the CLI above exercises through a subprocess. scripts/read-config never
# requires this lib in process, so SimpleCov could never see these lines
# through the suite above alone (intent 397, lead's gate-failure item 3).
class ReadConfigLibTest < Minitest::Test
  def setup
    @global_dir = Dir.mktmpdir("plastic-global-lib")
    @project_dir = Dir.mktmpdir("plastic-project-lib")
    FileUtils.mkdir_p(File.join(@project_dir, ".plastic_store"))
  end

  def teardown
    FileUtils.rm_rf(@global_dir)
    FileUtils.rm_rf(@project_dir)
  end

  def write_global_config(data)
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(data))
  end

  def write_project_config(data)
    File.write(File.join(@project_dir, ".plastic_store", "config.yml"), YAML.dump(data))
  end

  def options(**attrs)
    ReadConfig::Options.new(default: nil, project: nil, harness: nil, plastic_home: @global_dir, **attrs)
  end

  def test_resolve_returns_the_builtin_default_with_no_config
    assert_equal 3, ReadConfig.resolve("stale_threshold_days", options)
  end

  def test_resolve_prefers_project_over_global
    write_global_config("agent" => { "type" => "claude-code" })
    write_project_config("agent" => { "type" => "hermes" })

    assert_equal "hermes", ReadConfig.resolve("agent.type", options(project: @project_dir))
  end

  def test_resolve_returns_the_explicit_default_when_nothing_configured
    assert_equal "fallback", ReadConfig.resolve("nonexistent.key", options(default: "fallback"))
  end

  def test_resolve_keeps_a_stored_false_instead_of_falling_through
    write_global_config("runner" => { "stop_hook" => true })

    assert ReadConfig.resolve("runner.stop_hook", options)
  end

  def test_resolve_reads_harness_scoped_agent_models
    write_global_config("agents" => { "models" => { "claude" => { "plastic-executor" => "haiku" } } })

    assert_equal "haiku", ReadConfig.resolve("agents.models.plastic-executor", options(harness: "claude"))
  end

  def test_resolve_falls_back_to_the_shipped_model_for_an_unconfigured_agent
    assert_equal "gpt-5.6-terra", ReadConfig.resolve("agents.models.plastic-executor", options(harness: "codex"))
  end

  def test_harness_canonical_accepts_claude_code_as_claude
    assert_equal "claude", ReadConfig::Harness.canonical("claude-code")
  end

  def test_harness_canonical_returns_nil_for_no_value
    assert_nil ReadConfig::Harness.canonical(nil)
  end

  def test_harness_canonical_rejects_an_unknown_harness
    assert_raises(ReadConfig::InvalidHarness) { ReadConfig::Harness.canonical("unknown") }
  end

  def test_format_value_renders_a_hash_as_json
    assert_equal '{"a":1}', ReadConfig.format_value({ "a" => 1 })
  end

  def test_format_value_renders_booleans_and_numbers_as_strings
    assert_equal "false", ReadConfig.format_value(false)
    assert_equal "3", ReadConfig.format_value(3)
  end

  def test_format_value_renders_nil_as_empty
    assert_equal "", ReadConfig.format_value(nil)
  end

  def test_load_yaml_warns_and_returns_empty_on_a_broken_file
    broken = File.join(@global_dir, "broken.yml")
    File.write(broken, "{not: valid: yaml")

    _out, err = capture_io { assert_equal({}, ReadConfig.load_yaml(broken)) }

    assert_includes err, "Warning: failed to parse"
  end
end

class ReadConfigMigrateTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/read-config", __FILE__)

  def setup
    @global_dir = Dir.mktmpdir("plastic-global")
  end

  def teardown
    FileUtils.rm_rf(@global_dir)
  end

  def test_migrate_adds_missing_agent_section
    v2_config = {
      "version" => 2,
      "project_roots" => ["~/.plastic/projects"],
      "stale_threshold_days" => 3,
      "execution_mode" => "subagent-driven",
      "hash_length" => 6,
      "hash_algorithm" => "sha256-base36",
      "max_slug_words" => 5
    }
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(v2_config))

    env = { "PLASTIC_HOME" => @global_dir }
    stdout, _, status = Open3.capture3(env, SCRIPT, "--migrate")
    assert status.success?

    migrated = YAML.safe_load(File.read(File.join(@global_dir, "config.yml")))
    assert_equal 3, migrated["version"]
    assert_equal "claude-code", migrated["agent"]["type"]
    assert_equal "linear", migrated["agent"]["parallel_mode"]
    assert_kind_of Hash, migrated["architect"]
  end

  def test_migrate_preserves_existing_values
    config = {
      "version" => 2,
      "stale_threshold_days" => 7,
      "project_roots" => ["~/my-projects"],
      "execution_mode" => "subagent-driven",
      "hash_length" => 6,
      "hash_algorithm" => "sha256-base36",
      "max_slug_words" => 5
    }
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(config))

    env = { "PLASTIC_HOME" => @global_dir }
    Open3.capture3(env, SCRIPT, "--migrate")

    migrated = YAML.safe_load(File.read(File.join(@global_dir, "config.yml")))
    assert_equal 7, migrated["stale_threshold_days"]
    assert_equal ["~/my-projects"], migrated["project_roots"]
  end

  def test_migrate_noop_when_already_v3
    config = {
      "version" => 3,
      "agent" => { "type" => "hermes", "parallel_mode" => "hermes-batch" },
      "architect" => { "style" => "go-stdlib" },
      "stale_threshold_days" => 3
    }
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(config))

    env = { "PLASTIC_HOME" => @global_dir }
    stdout, _, status = Open3.capture3(env, SCRIPT, "--migrate")
    assert status.success?
    assert_includes stdout, "already"

    after = YAML.safe_load(File.read(File.join(@global_dir, "config.yml")))
    assert_equal "hermes", after["agent"]["type"]
  end
end
