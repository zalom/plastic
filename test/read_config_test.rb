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
    env = { "PLASTIC_GLOBAL_ROOT" => global_dir }
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
