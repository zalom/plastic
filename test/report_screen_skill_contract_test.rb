# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# The human report contract names the report screens, their triggers and the
# rules every harness follows when it prints one.
class ReportScreenSkillContractTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def read(rel)
    File.read(File.join(REPO, rel))
  end

  def contract = read("docs/help/human-report-contract.md")

  def test_human_report_contract_names_the_three_screens
    %w[state delivered delay].each { |screen| assert_includes contract, "report-screen #{screen}" }
  end

  def test_human_report_contract_names_the_verdict_merge_and_release_triggers
    %w[verdict merge release].each { |trigger| assert_includes contract, trigger }
  end

  def test_human_report_contract_states_cross_harness_neutrality
    ["every harness", "harness name"].each { |phrase| assert_includes contract, phrase }
  end

  def test_outcome_template_names_the_owning_heading
    assert_includes read("templates/outcome.md"), "owns the matrix table"
  end

  def test_human_report_contract_names_the_session_screen
    assert_includes contract, "report-screen session"
  end

  def test_human_report_contract_names_the_plan_screen_before_delivery
    ["report-screen plan", "pre-delivery", "How boundary"].each { |phrase| assert_includes contract, phrase }
  end

  def test_changelog_names_the_plan_screen
    text = read("CHANGELOG.md")

    ["331b", "report-screen plan"].each { |phrase| assert_includes text, phrase }
  end

  def test_contract_states_column_vocabulary
    text = contract.gsub(/\s+/, " ")

    ["Graph ID", "before its first colon"].each { |phrase| assert_includes text, phrase }
  end
end
