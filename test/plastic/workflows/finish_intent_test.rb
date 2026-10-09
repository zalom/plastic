# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/finish_intent"

class FinishIntentTest < Plastic::TestCase
  def finish(requirements: [], judged: false)
    run_workflow(Plastic::Workflows::FinishIntent, intent_id: "1", requirements:, judged:, intent_folder: "store/1--alpha").first
  end

  def test_nothing_missing_is_done
    assert_equal :done, finish(judged: true)
  end

  def test_missing_records_are_handed_to_the_agent
    assert_equal "Complete these recorded prerequisites: outcome.md", finish(requirements: ["outcome.md"], judged: true).steps.first
  end

  def test_no_counting_verdict_names_the_judge_command
    assert_includes finish.steps.join("\n"), "plastic intent judge 1"
  end

  def test_the_steps_name_neither_removed_option
    text = finish(requirements: ["outcome.md"]).steps.join("\n")

    ["--judge", "--evidence", "completion.json"].each { |part| refute_includes text, part }
  end
end
