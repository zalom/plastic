# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/role_files"
require "plastic/installations/codex_agents"

# Done criterion of intent 543: a helper never ends its turn to wait on a background job. It runs each check in the
# foreground and splits a long suite into its layers. Every harness copy installed from the role files says so.
class ForegroundChecksRoleTest < Plastic::TestCase
  include PackageFixture

  ROOT = PackageFixture::REAL_PACKAGE
  ROLES = %w[plastic-executor plastic-driver].freeze
  RULES = ["never ends its turn to wait on a background job", "runs each check in the foreground and reads the result itself",
    "splits a long suite into its layers"].freeze

  def flat(text) = text.gsub(/\s+/, " ")

  def says_the_rules(text) = RULES.map { |rule| flat(text).include?(rule) }

  def test_each_role_file_says_a_helper_runs_its_checks_in_the_foreground
    assert_equal [[true] * 3] * 2, ROLES.map { |name| says_the_rules(File.read(File.join(ROOT, "agents", "#{name}.md"))) }
  end

  def test_the_copies_installed_for_claude_code_and_hermes_say_it
    Plastic::Installations::RoleFiles.new(ROOT).call(File.join(@home, "agents"))

    assert_equal [[true] * 3] * 2, ROLES.map { |name| says_the_rules(File.read(File.join(@home, "agents", "#{name}.md"))) }
  end

  def test_the_copies_installed_for_codex_say_it
    Plastic::Installations::CodexAgents.new(ROOT).call(File.join(@home, "codex"))

    assert_equal [[true] * 3] * 2, ROLES.map { |name| says_the_rules(File.read(File.join(@home, "codex", "#{name}.toml")).gsub("\\n", "\n")) }
  end
end
