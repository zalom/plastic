require "minitest/autorun"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"
require "open3"

class DeprecationDisplayTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/hook-session-start", __FILE__)

  def setup
    @store_root = Dir.mktmpdir("plastic-store")
    @plugin_root = Dir.mktmpdir("plastic-plugin")
    FileUtils.mkdir_p("#{@store_root}/store/1--test-intent")
    FileUtils.mkdir_p("#{@plugin_root}/.claude-plugin")
    FileUtils.mkdir_p("#{@plugin_root}/scripts")

    write_index("## Active\n- [1 — Test intent](store/1--test-intent/1--test-intent.md) — test\n\n## Future\n")
    write_intent("1--test-intent", id: "1", intent: "Test", created: "2026-06-07")
    write_plugin_json("0.9.0")
    write_read_config_shim
  end

  def teardown
    FileUtils.rm_rf(@store_root)
    FileUtils.rm_rf(@plugin_root)
  end

  def test_empty_deprecations_no_output
    write_deprecations([])
    output = run_hook
    refute_match(/DEPRECATION/, output)
    refute_match(/Deprecation/, output)
  end

  def test_info_severity_single_line
    write_deprecations([{
      "id" => "test-feature",
      "severity" => "info",
      "summary" => "Feature X is being removed",
      "migration_steps" => ["Do Y"],
      "introduced" => "0.9.0",
      "removal" => "1.0.0",
      "link" => "https://example.com/migrate"
    }])
    output = run_hook
    assert_match(/Deprecation: Feature X is being removed/, output)
    assert_match(/Removed in: 1\.0\.0/, output)
    assert_match(/See: https:\/\/example\.com\/migrate/, output)
    refute_match(/Migration steps/, output)
  end

  def test_warning_severity_block_format
    write_deprecations([{
      "id" => "test-warning",
      "severity" => "warning",
      "summary" => "Plugin distribution changing",
      "migration_steps" => ["Uninstall old plugin", "Run npx install"],
      "introduced" => "0.9.0",
      "removal" => "1.0.0"
    }])
    output = run_hook
    assert_match(/DEPRECATION \(warning\): Plugin distribution changing/, output)
    assert_match(/Migration steps/, output)
    assert_match(/1\. Uninstall old plugin/, output)
    assert_match(/2\. Run npx install/, output)
    assert_match(/Removed in: 1\.0\.0/, output)
  end

  def test_critical_severity_block_format
    write_deprecations([{
      "id" => "test-critical",
      "severity" => "critical",
      "summary" => "Security vulnerability in auth",
      "migration_steps" => ["Update immediately"],
      "introduced" => "0.9.0",
      "removal" => "0.9.1"
    }])
    output = run_hook
    assert_match(/DEPRECATION \(critical\): Security vulnerability in auth/, output)
    assert_match(/Migration steps/, output)
  end

  def test_dismissed_deprecation_hidden
    write_deprecations([{
      "id" => "dismissed-one",
      "severity" => "warning",
      "summary" => "This should not show",
      "migration_steps" => ["Step 1"],
      "introduced" => "0.8.0",
      "removal" => "1.0.0"
    }])
    write_config("deprecations_dismissed" => ["dismissed-one"])
    output = run_hook
    refute_match(/This should not show/, output)
  end

  def test_critical_shown_even_when_dismissed
    write_deprecations([{
      "id" => "critical-dismissed",
      "severity" => "critical",
      "summary" => "Critical cannot be hidden",
      "migration_steps" => ["Act now"],
      "introduced" => "0.9.0",
      "removal" => "1.0.0"
    }])
    write_config("deprecations_dismissed" => ["critical-dismissed"])
    output = run_hook
    assert_match(/Critical cannot be hidden/, output)
  end

  def test_at_removal_version_shown_despite_dismissal
    write_plugin_json("1.0.0")
    write_deprecations([{
      "id" => "at-removal",
      "severity" => "warning",
      "summary" => "Final warning before removal",
      "migration_steps" => ["Migrate now"],
      "introduced" => "0.9.0",
      "removal" => "1.0.0"
    }])
    write_config("deprecations_dismissed" => ["at-removal"])
    output = run_hook
    assert_match(/Final warning before removal/, output)
  end

  def test_malformed_yaml_no_crash
    File.write("#{@plugin_root}/deprecations.yml", "{{invalid yaml: [")
    output = run_hook
    refute_match(/DEPRECATION/, output)
  end

  private

  def run_hook
    index_path = "#{@store_root}/INDEX.md"
    # PLASTIC_TMP + session isolation (intent 108): with one active intent in
    # the fixture INDEX, hook-session-start DERIVES a bridge; unisolated it
    # wrote /tmp/plastic-<live session id>.json with intent "1" test data
    # (the 107/110 live-bridge clobber, reproduced by this very test).
    env = { "PLASTIC_HOME" => @store_root,
            "PLASTIC_TMP" => @plugin_root, "CLAUDE_CODE_SESSION_ID" => nil }
    cmd = ["ruby", SCRIPT, index_path, @store_root, "global", @plugin_root]
    stdout, _stderr, _status = Open3.capture3(env, *cmd)
    return "" if stdout.strip.empty?
    data = JSON.parse(stdout)
    data.dig("hookSpecificOutput", "additionalContext") || ""
  end

  def write_index(content)
    File.write("#{@store_root}/INDEX.md", "# Index\n\n#{content}")
  end

  def write_intent(dir_name, id:, intent:, created:)
    content = <<~MD
      ---
      id: "#{id}"
      intent: #{intent}
      sources: []
      chain: []
      created: #{created}
      author: human
      tags: [test]
      ---

      ## Intent
      #{intent}

      ## Context
      ## Outcome
      ## Insights
      ## Links
    MD
    File.write("#{@store_root}/store/#{dir_name}/#{dir_name}.md", content)
  end

  def write_deprecations(list)
    File.write("#{@plugin_root}/deprecations.yml", YAML.dump("deprecations" => list))
  end

  def write_plugin_json(version)
    File.write("#{@plugin_root}/.claude-plugin/plugin.json", JSON.generate(
      "name" => "plastic", "version" => version
    ))
  end

  def write_config(data)
    File.write("#{@store_root}/config.yml", YAML.dump(data))
  end

  def write_read_config_shim
    shim = <<~'RUBY'
      #!/usr/bin/env ruby
      require "yaml"
      require "json"
      global_root = ENV.fetch("PLASTIC_HOME", File.expand_path("~/.plastic"))
      config_path = File.join(global_root, "config.yml")
      config = File.exist?(config_path) ? (YAML.safe_load(File.read(config_path)) || {}) : {}
      key = ARGV[0]
      value = config[key]
      value = [] if value.nil? && key == "deprecations_dismissed"
      value = 3 if value.nil? && key == "stale_threshold_days"
      case value
      when Hash, Array then puts JSON.generate(value)
      when nil then puts ""
      else puts value.to_s
      end
    RUBY
    path = "#{@plugin_root}/scripts/read-config"
    File.write(path, shim)
    File.chmod(0o755, path)
  end
end
