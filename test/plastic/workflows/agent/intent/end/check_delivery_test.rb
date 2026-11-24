# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/workflows/agent/intent/end/check_delivery"

class CheckDeliveryTest < Plastic::TestCase
  FOUND = "The repository has a pull request template at pull_request_template.md; the description of the pull request follows it. "

  def check(delivery_recorded: false, template_found: "", delivery_found: "")
    run_workflow(Plastic::Workflows::Agent::Intent::End::CheckDelivery, intent_id: "1", intent_folder: "store/1--alpha", delivery_found:, template_found:,
      delivery_recorded:).first
  end

  def test_the_missing_delivery_prints_its_step_and_no_map_step
    steps = check.steps

    assert_equal ["Record the delivery"], steps.map { |text| text[/Record the delivery/] }
    refute_includes steps.join, "architecture map"
  end

  def test_a_recorded_delivery_is_done
    assert_equal :done, check(delivery_recorded: true)
  end

  def test_the_steps_name_the_labels_the_folder_and_the_end_command
    text = check.steps.join("\n")

    refute_includes text, "Architecture map"
    ["- Merged: ", "- Committed: ", "- Delivered: ", "Verification", "store/1--alpha/outcome.md", "plastic store sync up",
      "plastic intent end 1"].each do |part|
      assert_includes text, part
    end
  end

  def test_the_delivery_step_says_where_delivered_files_go_and_when_they_count
    step = check.steps.first

    ["store/1--alpha/resources/output/reports", "store/1--alpha/resources/output/files", "only for work that no version control holds"].each do |part|
      assert_includes step, part
    end
  end

  def test_the_steps_say_plastic_runs_no_version_control_command
    assert_includes check.steps.join("\n"), "Plastic runs no version control command"
  end

  def test_the_delivery_step_tells_the_agent_to_use_version_control_as_the_project_defines_it
    step = check.steps.first

    assert_includes step, "use version control, such as Git, as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: " \
      "merge the pull request of intent 1 into the intent's base, and leave it open only when the owner asked."
    refute_includes step, "your own"
  end

  def test_the_delivery_step_prints_the_template_fact_after_the_owner_clause
    assert_includes check(template_found: FOUND).steps.first, "leave it open only when the owner asked. #{FOUND}"
  end

  def test_the_delivery_step_starts_with_the_line_it_found_out_of_form
    found = "outcome.md says 'Merged: no', which is not a delivery line in its form. "

    assert check(delivery_found: found).steps.first.start_with?(found)
  end

  def test_the_delivery_step_without_a_template_says_nothing_of_one
    refute_includes check.steps.first, "pull request template"
  end

  def test_the_steps_name_neither_removed_option
    text = check.steps.join("\n")

    ["--judge", "--evidence"].each { |option| refute_includes text, option }
  end
end
