require "minitest/autorun"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"
require "open3"

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

  def run_script(key, default: nil, global_dir: @global_dir, project_dir: nil)
    env = { "PLASTIC_HOME" => global_dir }
    args = [SCRIPT, key]
    args += ["--default", default] if default
    args += ["--project", project_dir] if project_dir
    stdout, stderr, status = Open3.capture3(env, *args)
    [stdout.strip, stderr.strip, status]
  end

  def write_global_config(data)
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(data))
  end

  def write_project_config(data)
    File.write(File.join(@project_store, "config.yml"), YAML.dump(data))
  end

  # Intent 312: the two absolute-token compaction thresholds resolve from DEFAULTS
  # with no config file present, and a config value wins over them.
  def test_context_thresholds_fall_back_to_the_shipped_defaults
    out, _, status = run_script("context_offer_tokens")
    assert status.success?
    assert_equal "350000", out

    out, _, status = run_script("context_insist_tokens")
    assert status.success?
    assert_equal "500000", out
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
