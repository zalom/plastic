# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/finish_intent"

class FinishIntentTest < Plastic::TestCase
  def finish(requirements: [], attestation: nil)
    run_workflow(Plastic::Workflows::FinishIntent, intent_id: "1", requirements:, attestation:, intent_folder: "store/1--alpha",
      evidence_example: "{}").first
  end

  def test_records_and_evidence_in_place_are_done
    assert_equal :done, finish(attestation: { "It works" => "green" })
  end

  def test_missing_records_are_handed_to_the_agent
    assert_equal "Complete these recorded prerequisites: outcome.md", finish(requirements: ["outcome.md"]).steps.first
  end

  def test_missing_evidence_names_the_folder_and_the_end_command
    step = finish.steps.find { |text| text.include?("completion.json") }

    assert_includes step, "Write completion.json inside store/1--alpha"
    assert_includes step, "plastic intent end 1 --judge tests|tool|agent|owner --evidence completion.json"
  end

  def test_the_map_step_lives_in_the_merge_check
    steps = finish(requirements: ["outcome.md"]).steps

    refute(steps.any? { |text| text.include?("architecture map") })
  end

  def test_open_records_and_no_evidence_print_records_and_evidence_in_order
    steps = finish(requirements: ["outcome.md"]).steps

    assert_equal ["prerequisites", "completion.json"], steps.map { |text| text[/prerequisites|completion\.json/] }
  end

  def test_the_evidence_step_names_the_criterion_keys
    assert_includes finish.steps.find { |text| text.include?("completion.json") }, "criterion key"
  end
end
