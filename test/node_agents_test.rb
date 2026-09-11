# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

require_relative "../scripts/lib/agent_models"
require_relative "../scripts/lib/harness_adapter"

# Intent 340b, G7c, n2: the three per-kind agent definitions (plastic-node-work,
# plastic-node-verify, plastic-node-research) that HarnessAdapter names for a Claude
# Code dispatch. Verify and research carry no `Bash`, because Claude Code's `tools:`
# field grants or withholds a whole tool name, never a command pattern, and a shell
# is a write. This file reads the real shipped agents/*.md tree, never a fixture.
class NodeAgentsTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  NODE_AGENTS = %w[plastic-node-work plastic-node-verify plastic-node-research].freeze
  READ_ONLY_AGENTS = %w[plastic-node-verify plastic-node-research].freeze

  def frontmatter(basename)
    content = File.read(File.join(REPO, "agents", "#{basename}.md"))
    front, _body = content.split(/^---\s*$/, 3).drop(1)
    YAML.safe_load(front)
  end

  def tools_for(basename)
    Array(frontmatter(basename)["tools"])
  end

  def body_for(basename)
    content = File.read(File.join(REPO, "agents", "#{basename}.md"))
    _blank, _front, body = content.split(/^---\s*$/, 3)
    body.to_s
  end

  # 2.1
  def test_work_agent_has_write_tools
    tools = tools_for("plastic-node-work")
    assert_includes tools, "Write"
    assert_includes tools, "Edit"
  end

  # 2.2
  def test_verify_agent_has_no_bash
    refute_includes tools_for("plastic-node-verify"), "Bash"
  end

  # 2.3
  def test_research_agent_has_no_bash
    refute_includes tools_for("plastic-node-research"), "Bash"
  end

  # 2.4
  def test_read_only_agents_can_read
    READ_ONLY_AGENTS.each do |basename|
      tools = tools_for(basename)
      assert_equal %w[Read Glob Grep].sort, tools.sort, "#{basename} must carry exactly Read, Glob, Grep"
    end
  end

  # 2.5
  def test_every_node_agent_declares_tools
    NODE_AGENTS.each do |basename|
      refute_empty tools_for(basename), "#{basename} must declare a tools: allowlist"
    end
  end

  # 2.6
  def test_agent_names_match_adapter_mapping
    mapped = HarnessAdapter::AGENT_TYPE_BY_KIND.values.sort
    assert_equal NODE_AGENTS.sort, mapped
    HarnessAdapter::AGENT_TYPE_BY_KIND.each_value do |basename|
      assert File.file?(File.join(REPO, "agents", "#{basename}.md")), "#{basename}.md must ship"
      assert_equal basename, frontmatter(basename)["name"], "#{basename}.md name: must match its own basename"
    end
  end

  # 2.7
  def test_every_node_agent_declares_model
    NODE_AGENTS.each do |basename|
      model = frontmatter(basename)["model"]
      refute_nil model, "#{basename} must declare a model:"
      refute_empty model.to_s, "#{basename} must declare a non-blank model:"
    end
  end

  # 2.14
  def test_work_agent_states_the_bash_caveat
    body = body_for("plastic-node-work")
    assert_match(/not a sandbox on what `Bash` can do/, body)
  end
end
