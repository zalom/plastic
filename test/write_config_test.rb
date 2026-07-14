require "minitest/autorun"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"
require "open3"

class WriteConfigTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/write-config", __FILE__)

  def setup
    @global_dir = Dir.mktmpdir("plastic-global")
  end

  def teardown
    FileUtils.rm_rf(@global_dir)
  end

  def run_script(*args, global_dir: @global_dir)
    env = { "PLASTIC_HOME" => global_dir }
    stdout, stderr, status = Open3.capture3(env, SCRIPT, *args)
    [stdout.strip, stderr.strip, status]
  end

  def read_config
    path = File.join(@global_dir, "config.yml")
    return {} unless File.exist?(path)
    YAML.safe_load(File.read(path)) || {}
  end

  def write_config(data)
    File.write(File.join(@global_dir, "config.yml"), YAML.dump(data))
  end

  def test_sets_top_level_scalar
    _out, _err, status = run_script("stale_threshold_days", "7")
    assert status.success?

    config = read_config
    assert_equal 7, config["stale_threshold_days"]
  end

  def test_sets_nested_key_creating_intermediate_hashes
    _out, _err, status = run_script("advisor.claude.default", "plastic-faux-advisor")
    assert status.success?

    config = read_config
    assert_equal "plastic-faux-advisor", config["advisor"]["claude"]["default"]
  end

  def test_preserves_existing_unrelated_keys
    write_config("version" => 3, "stale_threshold_days" => 3, "agent" => { "type" => "claude-code" })

    _out, _err, status = run_script("advisor.claude.default", "plastic-advisor")
    assert status.success?

    config = read_config
    assert_equal 3, config["version"]
    assert_equal 3, config["stale_threshold_days"]
    assert_equal "claude-code", config["agent"]["type"]
    assert_equal "plastic-advisor", config["advisor"]["claude"]["default"]
  end

  def test_push_appends_and_dedupes
    run_script("config_asks_dismissed", "--push", "advisor-default")
    _out, _err, status = run_script("config_asks_dismissed", "--push", "advisor-default")
    assert status.success?

    config = read_config
    assert_equal ["advisor-default"], config["config_asks_dismissed"]
  end

  def test_push_creates_array_when_key_absent
    _out, _err, status = run_script("config_asks_dismissed", "--push", "advisor-default")
    assert status.success?

    config = read_config
    assert_equal ["advisor-default"], config["config_asks_dismissed"]
  end

  def test_round_trips_with_read_config
    run_script("stale_threshold_days", "7")

    read_config_script = File.expand_path("../../scripts/read-config", __FILE__)
    env = { "PLASTIC_HOME" => @global_dir }
    stdout, _stderr, status = Open3.capture3(env, read_config_script, "stale_threshold_days")

    assert status.success?
    assert_equal "7", stdout.strip
  end

  # NOTE on write-config safety (intent 194): the owner's real config.yml has
  # no comments (it is machine-generated), so a whole-file YAML.dump rewrite
  # loses nothing. It does carry a legacy flat key
  # (agents.models.plastic-brainstorming: fable) and a nil
  # (architect.style:). This proves both survive a write-config round trip
  # untouched.
  def test_preserves_legacy_flat_key_and_nil_value
    write_config(
      "version" => 3,
      "agents" => { "models" => { "plastic-brainstorming" => "fable" } },
      "architect" => { "style" => nil },
    )

    _out, _err, status = run_script("stale_threshold_days", "7")
    assert status.success?

    config = read_config
    assert_equal "fable", config["agents"]["models"]["plastic-brainstorming"]
    assert config["architect"].key?("style")
    assert_nil config["architect"]["style"]
  end
end
