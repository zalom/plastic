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
  # (agents.models.plastic-executor: fable) and a nil
  # (architect.style:). This proves both survive a write-config round trip
  # untouched.
  def test_preserves_legacy_flat_key_and_nil_value
    write_config(
      "version" => 3,
      "agents" => { "models" => { "plastic-executor" => "fable" } },
      "architect" => { "style" => nil },
    )

    _out, _err, status = run_script("stale_threshold_days", "7")
    assert status.success?

    config = read_config
    assert_equal "fable", config["agents"]["models"]["plastic-executor"]
    assert config["architect"].key?("style")
    assert_nil config["architect"]["style"]
  end

  # --- Fix round: concurrency safety (proven live by an independent
  # reviewer: two unlocked concurrent writers silently lost one key). The
  # real code is now guarded by an flock held across the whole
  # read-modify-write plus a write-to-temp-then-rename, so both concurrent
  # writers' keys must survive regardless of which one the OS lets through
  # first. Real subprocesses via Open3.capture3, run from separate Threads so
  # the two write-config invocations genuinely overlap in wall-clock time.
  def test_concurrent_writes_do_not_lose_data
    results = []
    threads = [
      Thread.new { results << run_script("key_one", "1") },
      Thread.new { results << run_script("key_two", "2") },
    ]
    threads.each(&:join)

    assert results.all? { |_out, _err, status| status.success? },
      "both concurrent writers should succeed: #{results.inspect}"

    config = read_config
    assert_equal 1, config["key_one"], "the first concurrent writer's key must survive"
    assert_equal 2, config["key_two"], "the second concurrent writer's key must survive"
  end

  # --- Fix round: a malformed config.yml must refuse to write, not destroy
  # it. Silently degrading to {} (the way read-only read-config safely can)
  # would rewrite the owner's config.yml from an empty hash and destroy
  # whatever was in it -- a guard must fail milder than the bug, not worse.
  def test_refuses_to_write_when_config_yml_is_malformed
    config_path = File.join(@global_dir, "config.yml")
    broken = "not: valid: yaml: ["
    File.write(config_path, broken)
    before = File.binread(config_path)

    _out, err, status = run_script("stale_threshold_days", "7")

    refute status.success?, "write-config must exit non-zero on an unparseable config.yml"
    refute_empty err, "write-config must explain why it refused, on stderr"
    assert_match(/config\.yml/, err)

    after = File.binread(config_path)
    assert_equal before, after, "a malformed config.yml must be left byte-for-byte unchanged"
  end

  # A config.yml that parses cleanly but is not a mapping (a bare string, a
  # top-level list) slipped past the parse-error rescue and died with a raw
  # IndexError/TypeError backtrace. It failed closed, but a guard in a batch
  # about tools that degrade badly must refuse in one readable line.
  def test_refuses_to_write_when_config_yml_is_not_a_mapping
    config_path = File.join(@global_dir, "config.yml")
    ["just a bare string\n", "- one\n- two\n"].each do |not_a_mapping|
      File.write(config_path, not_a_mapping)
      before = File.binread(config_path)

      _out, err, status = run_script("stale_threshold_days", "7")

      refute status.success?,
        "write-config must exit non-zero on a config.yml that is not a mapping: #{not_a_mapping.inspect}"
      assert_match(/does not hold a key\/value mapping/, err,
        "write-config must refuse in one readable line, not a Ruby backtrace")
      refute_match(/IndexError|TypeError|backtrace/, err,
        "write-config must not leak a raw exception to the user")
      assert_equal before, File.binread(config_path),
        "a non-mapping config.yml must be left byte-for-byte unchanged"
    end
  end
end
