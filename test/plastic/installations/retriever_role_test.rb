# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/role_files"
require "plastic/installations/codex_agents"

# Done criterion of intent 519: the read-only retrieval role ships and installs for both harnesses.
class RetrieverRoleTest < Plastic::TestCase
  include PackageFixture

  ROOT = PackageFixture::REAL_PACKAGE

  def role = File.read(File.join(ROOT, "agents", "plastic-retriever.md"))

  def test_the_role_file_limits_its_tools_to_what_it_needs
    assert_includes role, "tools: Read, Grep, Glob, Bash, Write"
  end

  def test_the_role_file_claims_and_finishes_its_node
    assert_equal [true] * 3, ["plastic node claim", "plastic node done", "plastic node fail"].map { |text| role.include?(text) }
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
