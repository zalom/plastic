# frozen_string_literal: true

require_relative "../../../test_helper"

module OutcomeHelpers
  def setup
    super
    @intent = open_intent
  end

  def read_outcome = Plastic::Graph::Knowledge::Outcome.new(retrieval, "1")

  def outcome(body)
    write("#{@intent.dir}/outcome.md", body)
    sync_up
    read_outcome
  end

  def records(body)
    read = outcome(body)
    [read.merged?, read.architecture_map?]
  end

  def merged_value?(value) = outcome("## Verification\n- Merged: #{value}\n").merged?

  def approved_value?(value) = outcome("## Verification\n- Approved: #{value}\n").approved?
end

class KnowledgeOutcomeTest < Plastic::TestCase
  include OutcomeHelpers

  def test_both_labels_under_verification_count
    assert_equal [true, true], records("# Outcome\n\n## Verification\n- Merged: branch into alpha at abc1\n- Architecture map: enola at abc\n")
  end

  def test_a_merge_line_outside_verification_does_not_count
    assert_equal [false, false], records("# Outcome\n\n- Merged: branch into alpha at abc\n\n## Verification\n- Tests pass\n\n## Notes\n- Architecture map: enola\n")
  end

  def test_a_label_with_no_text_does_not_count
    assert_equal [false, false], records("## Verification\n- Merged:\n- Architecture map:   \n")
  end

  def test_labels_match_with_a_checkbox_and_any_case
    assert_equal [true, true], records("## Verification\n- [x] merged: branch into alpha at abc1\n- [ ] ARCHITECTURE MAP: enola\n")
  end

  def test_no_outcome_records_neither
    read = read_outcome

    assert_equal [false, false], [read.merged?, read.architecture_map?]
  end

  def test_a_bold_label_counts
    assert_equal [true, true], records("## Verification\n- **Merged:** branch into alpha at abc1\n- **Architecture map**: enola\n")
  end

  def test_a_star_bullet_counts
    assert_equal [true, false], records("## Verification\n* Merged: branch into alpha at abc1\n")
  end

  def test_bullets_under_a_subheading_of_verification_count
    assert_equal [true, true], records("## Verification\n### Merge\n- Merged: branch into alpha at abc1\n### Map\n- Architecture map: enola\n")
  end

  def test_a_third_level_verification_heading_counts
    assert_equal [true, false], records("### Verification\n- Merged: branch into alpha at abc1\n#### Detail\n- other\n## Next\n- Architecture map: enola\n")
  end

  def test_pull_request_approval_and_revert_bullets_are_read
    read = outcome("# Outcome\n\n## Verification\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-09\n- Reverted: nothing delivered\n")

    assert_equal [true, true, true], [read.pull_request?, read.approved?, read.reverted?]
  end
end

class KnowledgeOutcomeValuesTest < Plastic::TestCase
  include OutcomeHelpers

  NOT_MERGED = [
    "<branch> into <base> at <commit or pull request>", "not yet", "Not merged", "no", "No, the pull request is open", "awaiting review", "open",
    "waiting for CI", "unmerged", "never", "?", "\u2014", "0", "n.a.", "TODO", "false", "[ ] not merged", "`no`", "**no**", "\"no\"", "(pending)",
    "No-op change merged into alpha at abc", "N/A, merged by the owner at abc", "none needed, the change is docs only, pushed to alpha at abc",
    "Nothing to merge; the branch was empty", "yes", "x into alpha at TBD", "x into alpha at ?", "alpha at pending", "-"
  ].freeze

  MERGED = ["plastic/446--batch-3 into alpha at 2888a334", "branch into alpha at PR 9", "alpha at abc123", "x into main at pull request 58",
    "plastic/1 into alpha at abc123, then rebased"].freeze

  NOT_APPROVED = ["waiting for the owner", "requested", "no", "none", "pending", "not yet", "No objection from the owner",
    "<person> on <YYYY-MM-DD>", "by <person> on <date>", "by the owner on tomorrow"].freeze

  APPROVED = ["by the owner on 2026-11-14", "the owner on 2026-10-05", "Zed on 2026-10-05 in the pull request"].freeze

  def test_only_a_value_in_the_printed_form_of_merged_is_a_merge
    assert_equal [[], []], [NOT_MERGED.select { |value| merged_value?(value) }, MERGED.reject { |value| merged_value?(value) }]
  end

  def test_only_a_value_in_the_printed_form_of_approved_is_an_approval
    assert_equal [[], []], [NOT_APPROVED.select { |value| approved_value?(value) }, APPROVED.reject { |value| approved_value?(value) }]
  end

  NEGATIVE_APPROVED = ["no, changes requested on 2026-11-14", "pending review on 2026-11-20", "not yet, review due on 2026-11-20", "none on 2026-11-14",
    "rejected by Zlatko on 2026-11-14", "awaiting review on 2026-11-14", "changes requested on 2026-11-14", "declined on 2026-11-14",
    "denied by the owner on 2026-11-14", "requested on 2026-11-14"].freeze

  NEGATIVE_MERGED = ["pending at PR #57", "TBD at 2026-11-20", "not into alpha at 1"].freeze

  def test_an_approved_line_whose_first_word_is_negative_does_not_count
    assert_empty NEGATIVE_APPROVED.select { |value| approved_value?(value) }
  end

  def test_a_merged_line_whose_first_word_is_negative_does_not_count
    assert_empty NEGATIVE_MERGED.select { |value| merged_value?(value) }
  end

  def test_angle_brackets_count_unless_they_hold_a_placeholder_of_the_printed_form
    values = ["Zlatko <z@example.com> on 2026-11-14", "<person> on 2026-11-14", "Zlatko on <YYYY-MM-DD>"]

    assert_equal [true, false, false], values.map { |value| approved_value?(value) }
  end

  def test_the_last_part_of_a_merged_line_holds_a_digit_or_is_seven_to_forty_hex_characters
    counted = ["plastic/1 into alpha at deadbee", "plastic/1 into alpha at `deadbee`", "plastic/1 into alpha at https://github.com/example/repo/commit/abc1234"]
    refused = ["plastic/1 into alpha at deadbe", "plastic/1 into alpha at deadbeefoo", "plastic/1 into alpha at <sha>"]

    assert_equal [[true] * 3, [false] * 3], [counted, refused].map { |values| values.map { |value| merged_value?(value) } }
  end
end

class KnowledgeOutcomeMessagesTest < Plastic::TestCase
  include OutcomeHelpers

  def test_more_than_one_space_between_the_parts_of_a_merged_line_counts
    assert merged_value?("plastic/x  into alpha at 3f2a1b9")
  end

  def test_a_branch_of_more_than_one_word_is_refused_and_the_refusal_shows_the_form
    refused = ["PR #57 into alpha at 3f2a1b9", "pull request #57 into alpha at 3f2a1b9", "plastic/x into alpha via PR #57 at 3f2a1b9"]
    read = outcome("## Verification\n- Merged: #{refused.first}\n")

    assert_equal [[false] * 3, true], [refused.map { |value| merged_value?(value) }, read.missing_records.first.include?("Merged: <branch> into <base> at <commit or pull request>")]
  end

  def test_an_approved_date_followed_by_a_time_counts
    assert approved_value?("the owner on 2026-11-14T10:00Z")
  end

  def test_the_label_of_approved_needs_its_colon_directly
    refute_predicate outcome("## Verification\n- Approved by: the owner on 2026-11-14\n"), :approved?
  end

  def test_a_negative_word_in_another_label_still_counts_as_recorded
    read = outcome("## Verification\n- Architecture map: none found by tool X\n- Pull request: no link yet\n")

    assert_equal [true, true], [read.architecture_map?, read.pull_request?]
  end

  def test_the_missing_record_message_quotes_the_value_and_shows_the_form_to_write
    message = outcome("## Verification\n- Merged: N/A, merged by the owner at abc\n").missing_records.first

    assert_includes message, "Merged: N/A, merged by the owner at abc"
    assert_includes message, "Merged: <branch> into <base> at <commit or pull request>"
  end

  def test_a_value_out_of_form_is_named_with_its_label_and_a_value_in_form_or_an_absent_one_is_not
    read = outcome("## Verification\n- Approved: none\n- Merged: plastic/1 into alpha at abc123\n")

    assert_equal ["Approved: none", nil, nil], [read.rejected("Approved"), read.rejected("Merged"), read.rejected("Pull request")]
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
