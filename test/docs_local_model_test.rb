# frozen_string_literal: true

require_relative "test_helper"

# Intent 525: the driver docs say how to run a worker on a local model, for each harness.
class DocsLocalModelTest < Plastic::TestCase
  ROOT = File.expand_path("..", __dir__)
  DOC = File.read(File.join(ROOT, "docs/usage/drive-from-any-harness.md")).gsub(/\s+/, " ")

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

  def test_the_docs_name_the_requirements_and_the_node_path
    ["does not support tools", "64k", "--skip-git-repo-check", "No default OSS provider configured. Use --local-provider=provider", "`work` goes to `plastic-executor`", "plastic node claim ID NODE --agent NAME --json", "`total_cost_usd` as 0", "no base URL"].each { |phrase| assert_includes DOC, phrase }
  end

  def test_the_official_sources_are_cited
    ["https://docs.ollama.com/integrations/claude-code", "https://docs.ollama.com/integrations/codex"].each { |url| assert_includes DOC, url }
  end

  # A wrong command in the docs fails here: each documented `plastic config set` runs on the test home.
  def test_each_documented_config_set_command_runs_on_a_scratch_home
    commands = DOC.scan(/plastic config set agents\.models\.\S+ \S+ --harness \S+/)

    refute_empty commands
    commands.each do |line|
      result = plastic(*line.split.drop(1), table: Plastic::CLI::TABLE)

      assert_equal 0, result.code, "#{line}: #{result.err}"
    end
  end
end
