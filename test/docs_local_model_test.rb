# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "support/child_process"

# Intent 525: the driver docs say how to run a worker on a local model, for each harness.
class DocsLocalModelTest < Minitest::Test
  DOC = File.read(File.expand_path("../docs/usage/drive-from-any-harness.md", __dir__)).gsub(/\s+/, " ")

  def test_the_claude_code_section_names_the_base_url_the_token_and_the_model_flag
    ["## Run a worker on a local model", "### Claude Code on a local Ollama server", "ANTHROPIC_BASE_URL=http://localhost:11434", "ANTHROPIC_AUTH_TOKEN=ollama", "claude -p", "--model"].each { |phrase| assert_includes DOC, phrase }
  end

  def test_the_codex_section_names_the_oss_flags
    ["### Codex on a local Ollama server", "codex exec --oss", "--local-provider ollama", "oss_provider"].each { |phrase| assert_includes DOC, phrase }
  end

  def test_the_model_of_a_role_is_set_with_the_agents_models_setting
    assert_includes DOC, "plastic config set agents.models.plastic-executor"
    assert_includes DOC, "plastic install --reinstall"
  end

  def test_the_official_sources_are_cited
    ["https://docs.ollama.com/integrations/claude-code", "https://docs.ollama.com/integrations/codex"].each { |url| assert_includes DOC, url }
  end

  # A wrong command in the docs fails here: each documented `plastic config set` runs on a scratch home.
  def test_each_documented_config_set_command_runs_on_a_scratch_home
    root = File.expand_path("..", __dir__)
    commands = File.read(File.join(root, "docs/usage/drive-from-any-harness.md")).scan(/^plastic config set agents\.models\..+$/)

    refute_empty commands
    Dir.mktmpdir do |home|
      env = { "HOME" => home, "PLASTIC_HOME" => File.join(home, ".plastic"), "PLASTIC_TMP" => File.join(home, "tmp") }
      commands.each do |line|
        _out, err, status = ChildProcess.capture3(env, File.join(root, "exe", "plastic"), *line.split.drop(1), stdin_data: "")

        assert_equal 0, status.exitstatus, "#{line}: #{err}"
      end
    end
  end
end
