require "minitest/autorun"
require "tmpdir"
require "yaml"
require "fileutils"

BRIDGE_PATH = File.expand_path("../../scripts/lib/bridge.rb", __FILE__)
require BRIDGE_PATH

PROJ_CONFIG_TEST_HOME = File.join(Dir.tmpdir, "plastic-projcfg-test-#{Process.pid}")

class ProjectConfigTest < Minitest::Test
  def setup
    FileUtils.rm_rf(PROJ_CONFIG_TEST_HOME)
    FileUtils.mkdir_p(PROJ_CONFIG_TEST_HOME)
    @original_home = ENV["HOME"]
    ENV["HOME"] = PROJ_CONFIG_TEST_HOME
    FileUtils.mkdir_p(File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app"))
  end

  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(PROJ_CONFIG_TEST_HOME)
  end

  def test_returns_defaults_when_file_missing
    config = Bridge.read_project_config("nonexistent")
    assert_equal ["AGENTS.md"], config["governing_docs"]
    assert_equal "commit", config["release"]["on_complete"]
  end

  def test_returns_defaults_when_file_empty
    path = File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app", "project.yml")
    File.write(path, "")
    config = Bridge.read_project_config("test-app")
    assert_equal ["AGENTS.md"], config["governing_docs"]
    assert_equal "commit", config["release"]["on_complete"]
  end

  def test_merges_partial_config_over_defaults
    path = File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app", "project.yml")
    File.write(path, YAML.dump({
      "governing_docs" => ["CLAUDE.md"],
    }))
    config = Bridge.read_project_config("test-app")
    assert_equal ["CLAUDE.md"], config["governing_docs"]
    assert_equal "commit", config["release"]["on_complete"]
  end

  def test_merges_partial_release_config
    path = File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app", "project.yml")
    File.write(path, YAML.dump({
      "release" => { "on_complete" => "commit_and_push", "verify" => "bin/rails test" },
    }))
    config = Bridge.read_project_config("test-app")
    assert_equal ["AGENTS.md"], config["governing_docs"]
    assert_equal "commit_and_push", config["release"]["on_complete"]
    assert_equal "bin/rails test", config["release"]["verify"]
  end

  def test_complete_config
    path = File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app", "project.yml")
    File.write(path, YAML.dump({
      "governing_docs" => ["AGENTS.md", "CLAUDE.md"],
      "release" => {
        "on_complete" => "commit_and_push",
        "verify" => "ruby -Itest test/*_test.rb",
        "on_green" => ["github_release", "npm_publish"],
        "on_red" => "fix_and_retry",
        "tag_format" => "v{{version}}",
        "version_file" => "package.json",
      },
    }))
    config = Bridge.read_project_config("test-app")
    assert_equal ["AGENTS.md", "CLAUDE.md"], config["governing_docs"]
    assert_equal "commit_and_push", config["release"]["on_complete"]
    assert_equal ["github_release", "npm_publish"], config["release"]["on_green"]
    assert_equal "fix_and_retry", config["release"]["on_red"]
    assert_equal "v{{version}}", config["release"]["tag_format"]
    assert_equal "package.json", config["release"]["version_file"]
  end

  def test_handles_invalid_yaml
    path = File.join(PROJ_CONFIG_TEST_HOME, ".plastic", "projects", "test-app", "project.yml")
    File.write(path, "{{invalid yaml: [")
    config = Bridge.read_project_config("test-app")
    assert_equal ["AGENTS.md"], config["governing_docs"]
  end
end
