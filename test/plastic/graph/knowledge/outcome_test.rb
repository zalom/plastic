# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeOutcomeTest < Plastic::TestCase
  Outcome = Plastic::Graph::Knowledge::Outcome

  def setup
    super
    @intent = open_intent
  end

  def outcome(body)
    write("#{@intent.dir}/outcome.md", body)
    sync_up
    Outcome.new(retrieval, "1")
  end

  def records(body)
    read = outcome(body)
    [read.merged?, read.architecture_map?]
  end

  def test_both_labels_under_verification_count
    assert_equal [true, true], records("# Outcome\n\n## Verification\n- Merged: branch into alpha at abc\n- Architecture map: enola at abc\n")
  end

  def test_a_merge_line_outside_verification_does_not_count
    assert_equal [false, false], records("# Outcome\n\n- Merged: branch into alpha at abc\n\n## Verification\n- Tests pass\n\n## Notes\n- Architecture map: enola\n")
  end

  def test_a_label_with_no_text_does_not_count
    assert_equal [false, false], records("## Verification\n- Merged:\n- Architecture map:   \n")
  end

  def test_labels_match_with_a_checkbox_and_any_case
    assert_equal [true, true], records("## Verification\n- [x] merged: branch\n- [ ] ARCHITECTURE MAP: enola\n")
  end

  def test_no_outcome_records_neither
    read = Outcome.new(retrieval, "1")

    assert_equal [false, false], [read.merged?, read.architecture_map?]
  end

  def test_a_bold_label_counts
    assert_equal [true, true], records("## Verification\n- **Merged:** branch\n- **Architecture map**: enola\n")
  end

  def test_a_star_bullet_counts
    assert_equal [true, false], records("## Verification\n* Merged: branch\n")
  end

  def test_bullets_under_a_subheading_of_verification_count
    assert_equal [true, true], records("## Verification\n### Merge\n- Merged: branch\n### Map\n- Architecture map: enola\n")
  end

  def test_a_third_level_verification_heading_counts
    assert_equal [true, false], records("### Verification\n- Merged: branch\n#### Detail\n- other\n## Next\n- Architecture map: enola\n")
  end

  def test_pull_request_approval_and_revert_bullets_are_read
    read = outcome("# Outcome\n\n## Verification\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-09\n- Reverted: nothing delivered\n")

    assert_equal [true, true, true], [read.pull_request?, read.approved?, read.reverted?]
  end

  def merged_value?(value) = outcome("## Verification\n- Merged: #{value}\n").merged?

  def test_a_negative_value_of_merged_is_not_a_merge
    values = ["no", "pending", "-", "None yet", "N/A", "TBD", "false", "Not merged"]

    assert_equal values, values.reject { |value| merged_value?(value) }
  end

  def test_a_branch_named_like_a_negative_word_is_a_merge
    values = ["branch into alpha at PR 9", "node-sort into alpha", "pending-ui into alpha", "notes-fix at abc1"]

    assert_equal values, values.select { |value| merged_value?(value) }
  end

  def test_a_negative_value_of_approved_is_not_an_approval
    refute_predicate outcome("## Verification\n- Approved: none\n"), :approved?
  end

  def test_a_negative_word_in_another_label_still_counts_as_recorded
    read = outcome("## Verification\n- Architecture map: none found by tool X\n- Pull request: no link yet\n")

    assert_equal [true, true], [read.architecture_map?, read.pull_request?]
  end

  def test_the_missing_record_message_names_the_negative_value_it_found
    message = outcome("## Verification\n- Merged: no\n").missing_records.first

    assert_includes message, "Merged: no"
  end

  def test_the_missing_record_message_asks_for_a_merged_line_when_none_is_there
    message = outcome("## Verification\n- Architecture map: enola at abc123\n").missing_records.first

    assert_equal "Add a line starting Merged: to the Verification section of outcome.md and run plastic sync up.", message
  end

  def test_missing_pull_request_approval_and_revert_bullets_read_false
    read = outcome("# Outcome\n\n## Verification\n- Merged: into alpha\n")

    assert_equal [false, false, false], [read.pull_request?, read.approved?, read.reverted?]
  end
end
