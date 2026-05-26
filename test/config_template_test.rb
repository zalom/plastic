require "minitest/autorun"
require "yaml"

class ConfigTemplateTest < Minitest::Test
  TEMPLATE = File.expand_path("../../templates/config.yml", __FILE__)

  def setup
    @config = YAML.safe_load(File.read(TEMPLATE))
  end

  def test_version_is_3
    assert_equal 3, @config["version"]
  end

  def test_has_agent_section
    assert_kind_of Hash, @config["agent"]
    assert_equal "claude-code", @config["agent"]["type"]
    assert_equal "linear", @config["agent"]["parallel_mode"]
  end

  def test_has_architect_section
    assert_kind_of Hash, @config["architect"]
    assert_nil @config["architect"]["style"]
  end

  def test_has_stale_threshold
    assert_equal 3, @config["stale_threshold_days"]
  end

  def test_has_project_roots
    assert_kind_of Array, @config["project_roots"]
    assert_includes @config["project_roots"], "~/.plastic/projects"
  end

  def test_has_execution_mode
    assert_equal "subagent-driven", @config["execution_mode"]
  end
end
