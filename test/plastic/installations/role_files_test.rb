# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/role_files"

class RoleFilesTest < Plastic::TestCase
  include PackageFixture

  ROLES = { "demo-role" => PackageFixture::ROLE, "plastic-primary-advisor" => "---\nname: plastic-primary-advisor\nmodel: opus\n---\nAdvise.\n" }.freeze

  def copy(**options) = Plastic::Installations::RoleFiles.new(package(roles: ROLES), **options).call(File.join(@home, "agents"))

  def installed(name) = File.read(File.join(@home, "agents", "#{name}.md"))

  def test_a_role_file_is_copied_unchanged
    copy

    assert_equal PackageFixture::ROLE, installed("demo-role")
  end

  def test_a_model_override_rewrites_the_model_line
    copy(models: { "demo-role" => "opus" })

    assert_includes installed("demo-role"), "model: opus\n"
  end

  def test_an_effort_override_adds_an_effort_line_after_the_model
    copy(efforts: { "demo-role" => "high" })

    assert_includes installed("demo-role"), "model: sonnet\neffort: high\n"
  end

  def test_an_effort_override_replaces_an_effort_line
    roles = { "demo-role" => "---\nmodel: sonnet\neffort: low\n---\nBody\n" }
    Plastic::Installations::RoleFiles.new(package(roles:), efforts: { "demo-role" => "high" }).call(File.join(@home, "agents"))

    assert_includes installed("demo-role"), "effort: high\n"
  end

  def test_a_declined_advisor_installs_no_consultation_agent
    assert_equal [File.join(@home, "agents", "demo-role.md")], copy(skip: Plastic::Config::AgentModels::CONSULTATION_AGENTS)
  end

  def test_a_package_with_no_agents_copies_nothing
    root = File.join(@home, "empty")
    FileUtils.mkdir_p(root)

    assert_equal [], Plastic::Installations::RoleFiles.new(root).call(File.join(@home, "agents"))
  end

def test_the_worker_limit_replaces_its_placeholder_in_the_role_text
  roles = { "demo-role" => "---\nmodel: sonnet\n---\nRun {{driver.max_workers}} workers.\n" }
  Plastic::Installations::RoleFiles.new(package(roles:), workers: 4).call(File.join(@home, "agents"))

  assert_includes installed("demo-role"), "Run 4 workers.\n"
end

def test_the_shipped_driver_role_names_the_limit_by_its_placeholder
  text = File.read(File.join(PackageFixture::REAL_PACKAGE, "agents", "plastic-driver.md"))

  assert_includes text, "{{driver.max_workers}}"
end
end
