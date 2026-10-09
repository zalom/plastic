require "minitest/autorun"
require "yaml"

class ConfigTemplateTest < Minitest::Test
  TEMPLATE = File.expand_path("../../templates/config.yml", __FILE__)

  def setup
    @config = YAML.safe_load_file(TEMPLATE)
  end

  def test_the_template_is_config_version_3
    assert_equal 3, @config["version"]
  end

  def test_the_agent_section_names_claude_code_and_agent_teams
    assert_kind_of Hash, @config["agent"]
    assert_equal "claude-code", @config["agent"]["type"]
    assert_equal "agent-teams", @config["agent"]["parallel_mode"]
  end

  def test_the_architect_section_has_no_style_set
    assert_kind_of Hash, @config["architect"]
    assert_nil @config["architect"]["style"]
  end

  def test_an_intent_goes_stale_after_3_days
    assert_equal 3, @config["stale_threshold_days"]
  end

  def test_the_project_roots_include_the_plastic_projects_folder
    assert_kind_of Array, @config["project_roots"]
    assert_includes @config["project_roots"], "~/.plastic/projects"
  end

  def test_the_execution_mode_is_subagent_driven
    assert_equal "subagent-driven", @config["execution_mode"]
  end

  def test_a_pull_request_review_is_required_by_default
    assert_equal "required", @config.dig("review", "pull_request")
  end
end
