# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/codex_agents"

class CodexAgentsTest < Plastic::TestCase
  include PackageFixture

  ROLES = { "demo-role" => PackageFixture::ROLE, "plastic-primary-advisor" => "---\nname: plastic-primary-advisor\n---\nAdvise.\n" }.freeze

  def generate(roles = ROLES, **options) = Plastic::Installations::CodexAgents.new(package(roles:), **options).call(File.join(@home, "agents"))

  def test_each_role_file_becomes_a_toml_agent
    assert_equal [File.join(@home, "agents", "demo-role.toml"), File.join(@home, "agents", "plastic-primary-advisor.toml")], generate
  end

  def test_a_second_generation_is_byte_identical
    generate
    first = File.read(File.join(@home, "agents", "demo-role.toml"))
    generate

    assert_equal first, File.read(File.join(@home, "agents", "demo-role.toml"))
  end

  def test_a_declined_advisor_generates_no_consultation_agent
    assert_equal [File.join(@home, "agents", "demo-role.toml")], generate(skip: Plastic::Config::AgentModels::CONSULTATION_AGENTS)
  end

  def test_a_model_override_reaches_the_document
    generate(models: { "demo-role" => "gpt-x" })

    assert_includes File.read(File.join(@home, "agents", "demo-role.toml")), %(model = "gpt-x")
  end

  def test_a_package_with_no_role_files_generates_nothing
    assert_equal [[], false], [generate({}), File.exist?(File.join(@home, "agents"))]
  end
end
