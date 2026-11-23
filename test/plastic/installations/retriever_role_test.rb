# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/role_files"
require "plastic/installations/codex_agents"

# Done criterion of intent 519: the read-only retrieval role ships and installs for both harnesses.
class RetrieverRoleTest < Plastic::TestCase
  include PackageFixture

  ROOT = PackageFixture::REAL_PACKAGE

  def test_the_role_file_is_read_only_with_the_tools_it_needs
    text = File.read(File.join(ROOT, "agents", "plastic-retriever.md"))

    assert_includes text, "tools: Read, Grep, Glob, Bash, Write"
    assert_includes text, "plastic node claim"
    assert_includes text, "plastic node done"
    assert_includes text, "plastic node fail"
  end

  def test_it_installs_for_claude_code
    Plastic::Installations::RoleFiles.new(ROOT).call(File.join(@home, "agents"))

    assert_path_exists File.join(@home, "agents", "plastic-retriever.md")
  end

  def test_it_installs_for_codex
    Plastic::Installations::CodexAgents.new(ROOT).call(File.join(@home, "codex"))

    assert_path_exists File.join(@home, "codex", "plastic-retriever.toml")
  end
end
