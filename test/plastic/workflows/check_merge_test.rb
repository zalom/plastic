# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_merge"

class CheckMergeTest < Plastic::TestCase
  def check(merge_recorded: false, map_recorded: false)
    run_workflow(Plastic::Workflows::CheckMerge, intent_id: "1", intent_folder: "store/1--alpha", merge_recorded:, map_recorded:).first
  end

  def test_each_missing_record_prints_its_step
    steps = check.steps

    assert_equal ["merged", "architecture map"], steps.map { |text| text[/merged|architecture map/] }
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

  def test_the_steps_name_neither_removed_option
    text = check.steps.join("\n")

    ["--judge", "--evidence"].each { |option| refute_includes text, option }
  end
end
