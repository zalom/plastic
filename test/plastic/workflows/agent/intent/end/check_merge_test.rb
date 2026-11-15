# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/workflows/agent/intent/end/check_merge"

class CheckMergeTest < Plastic::TestCase
  FOUND = "The repository has a pull request template at pull_request_template.md; the description of the pull request follows it. "

  def check(merge_recorded: false, map_recorded: false, template_found: "")
    run_workflow(Plastic::Workflows::Agent::Intent::End::CheckMerge, intent_id: "1", intent_folder: "store/1--alpha", merge_found: "", template_found:, merge_recorded:, map_recorded:).first
  end

  def test_each_missing_record_prints_its_step
    steps = check.steps

    assert_equal ["Merge", "architecture map"], steps.map { |text| text[/Merge|architecture map/] }
  end

  def test_a_recorded_merge_leaves_only_the_map_step
    assert_equal 1, check(merge_recorded: true).steps.size
    assert_includes check(merge_recorded: true).steps.first, "architecture map"
  end

  def test_both_records_in_place_are_done
    assert_equal :done, check(merge_recorded: true, map_recorded: true)
  end

  def test_the_steps_name_the_labels_the_folder_and_the_end_command
    text = check.steps.join("\n")

    ["- Merged: ", "- Architecture map: ", "Verification", "store/1--alpha/outcome.md", "plastic sync up", "plastic intent end 1"].each do |part|
      assert_includes text, part
    end
  end

  def test_the_steps_say_plastic_runs_no_version_control_command
    assert_includes check.steps.join("\n"), "Plastic runs no version control command"
  end

  def test_the_merge_step_tells_the_agent_to_use_version_control_as_the_project_defines_it
    step = check.steps.first

    assert_includes step, "Use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: merge the pull request of intent 1 into the intent's base, and leave it open only when the owner asked."
    refute_includes step, "your own"
  end

  def test_the_merge_step_prints_the_template_fact_after_the_owner_clause
    assert_includes check(template_found: FOUND).steps.first, "leave it open only when the owner asked. #{FOUND}Then add"
  end

  def test_the_merge_step_without_a_template_says_nothing_of_one
    refute_includes check.steps.first, "pull request template"
  end

  def test_the_steps_name_neither_removed_option
    text = check.steps.join("\n")

    ["--judge", "--evidence"].each { |option| refute_includes text, option }
  end
end
