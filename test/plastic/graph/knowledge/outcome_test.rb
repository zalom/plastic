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
    read = Outcome.new(retrieval, "1")

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

  def merged_value?(value) = outcome("## Verification\n- Merged: #{value}\n").merged?

  def approved_value?(value) = outcome("## Verification\n- Approved: #{value}\n").approved?

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
