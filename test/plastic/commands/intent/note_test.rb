# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentNoteCaseTest < Plastic::TestCase
  def test_a_plain_note_prints_the_note_and_offers_next
    ran("intent new Alpha")

    assert_case line('intent note 1 "all checks pass"'), code: 0, out: ["note: all checks pass", "next: plastic next"]
  end

  def test_a_note_of_the_commit_kind_prints_the_commit_and_offers_next
    ran("intent new Alpha")

    assert_case line('intent note 1 "abc123 proves it" --kind Commit'), code: 0,
      out: ["commit: abc123 proves it", "next: plastic next"]
  end

  def test_a_merged_note_prints_the_line_and_offers_next
    ran("intent new Alpha")

    assert_case line(%(intent note 1 "plastic/1 into alpha at pull request 5" --kind Merged)), code: 0,
      out: ["merged: plastic/1 into alpha at pull request 5", "next: plastic next"]
  end

  def test_a_note_on_a_missing_intent_exits_1_and_names_it
    assert_case line('intent note 9 "text"'), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentNoteTest < Plastic::TestCase
  OUTCOME = "# Outcome\n\nDelivered.\n"
  FILE = "outcome.md"

  def call(*args) = plastic("intent", "note", *args, table: Plastic::CLI::TABLE)

  def body = retrieval.fetch("1", FILE).body

  def outcome_rows = store_graphs.databases.fetch(:store).rows("SELECT body FROM documents WHERE path = :path", path: FILE).map(&:values)

  def with_outcome(text = OUTCOME)
    intent = open_intent
    write("#{intent.dir}/#{FILE}", text)
    sync_up
    intent
  end

  def test_a_note_lands_under_a_notes_heading_and_keeps_the_text
    with_outcome

    result = call("1", "all checks pass")

    assert_equal 0, result.code, result.err
    assert_equal "#{OUTCOME}\n## Notes\n\n- Note: all checks pass\n", body
  end

  def test_a_note_of_the_report_kind_is_labeled_report
    with_outcome

    call("1", "the audit is in resources/output/reports/audit.md", "--kind", "report")

    assert_equal "#{OUTCOME}\n## Notes\n\n- Report: the audit is in resources/output/reports/audit.md\n", body
  end

  def test_a_second_note_goes_under_the_same_heading
    with_outcome

    call("1", "first")
    call("1", "second")

    assert_equal "#{OUTCOME}\n## Notes\n\n- Note: first\n- Note: second\n", body
  end

  def test_a_note_goes_at_the_end_of_an_existing_notes_section
    with_outcome("# Outcome\n\n## Notes\n\n- Review: earlier\n\n## Verification\n\n- Merged: yes\n")

    call("1", "later")

    assert_equal "# Outcome\n\n## Notes\n\n- Review: earlier\n- Note: later\n\n## Verification\n\n- Merged: yes\n", body
  end

  def test_the_kind_is_kept
    with_outcome

    call("1", "abc123 proves the rows", "--kind", "Commit")

    assert_includes body, "- Commit: abc123 proves the rows\n"
  end

  def test_an_unknown_kind_exits_2_and_writes_nothing
    with_outcome

    result = call("1", "text", "--kind", "Typo")

    assert_equal [2, OUTCOME, true], [result.code, body, result.err.include?("KIND takes Note, Review, Commit, Report, Merged, Committed, Delivered, Pull request, Approved, Reverted, Abandoned")]
  end

  def test_an_outcome_file_edited_by_hand_fails_the_note_and_writes_nothing
    intent = with_outcome
    write("#{intent.dir}/#{FILE}", "#{OUTCOME}\nEdited by hand.\n")
    before = outcome_rows
    result = call("1", "all checks pass")

    assert_equal [1, before, true], [result.code, outcome_rows, result.err.include?("run plastic store sync up first")]
  end

  def test_the_outcome_file_is_printed_from_the_rows
    intent = with_outcome

    call("1", "all checks pass")

    assert_equal body, File.read(store_path("#{intent.dir}/#{FILE}"))
  end

  def test_an_intent_with_no_outcome_gets_one_holding_the_note
    open_intent

    result = call("1", "first thought")

    assert_equal 0, result.code, result.err
    assert_equal "# Outcome\n\n## Notes\n\n- Note: first thought\n", body
  end

  def test_the_files_row_names_the_outcome_file
    intent = with_outcome

    result = call("1", "all checks pass", "--json")

    assert_includes JSON.parse(result.out).dig("result", "files"), "#{intent.dir}/#{FILE}"
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails_the_note_offers_next_and_writes_no_row") do
      open_intent(status:)
      before = outcome_rows

      result = call("1", "late thought")

      assert_equal [3, before], [result.code, outcome_rows]
      assert_includes result.err, "is #{status}"
      assert_match(/^next: plastic next/, result.out)
    end
  end

  def test_an_unknown_intent_fails_and_writes_nothing
    result = call("9", "text")

    assert_equal 1, result.code
    assert_empty(result.out.lines.grep(/^files:/))
  end
end

class IntentNoteVerificationTest < Plastic::TestCase
  OUTCOME = "# Outcome\n\nDelivered.\n"
  MERGED = "plastic/1 into alpha at pull request 5 (merge commit abc1234)"

  def call(*args) = plastic("intent", "note", *args, table: Plastic::CLI::TABLE)

  def body = retrieval.fetch("1", "outcome.md")&.body

  def with_outcome(text = OUTCOME)
    intent = open_intent
    write("#{intent.dir}/outcome.md", text)
    sync_up
    intent
  end

  def test_a_merged_note_lands_under_a_verification_heading
    with_outcome

    result = call("1", MERGED, "--kind", "Merged")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal "#{OUTCOME}\n## Verification\n\n- Merged: #{MERGED}\n", body
  end

  def test_the_kind_is_matched_without_regard_to_case_and_written_as_its_label
    with_outcome

    call("1", MERGED, "--kind", "merged")

    assert_includes body, "- Merged: #{MERGED}\n"
  end

  def test_a_kind_of_two_words_is_written_under_verification
    with_outcome

    result = call("1", "https://example.test/pull/5", "--kind", "pull request")

    assert_equal [0, "#{OUTCOME}\n## Verification\n\n- Pull request: https://example.test/pull/5\n"], [result.code, body]
  end

  def test_a_verification_line_goes_into_the_verification_section_at_any_level
    with_outcome("# Outcome\n\nDelivered.\n\n### Verification\n\n- Pull request: 5\n\n## Notes\n\n- Report: r\n")

    call("1", MERGED, "--kind", "Merged")

    assert_equal "# Outcome\n\nDelivered.\n\n### Verification\n\n- Pull request: 5\n- Merged: #{MERGED}\n\n## Notes\n\n- Report: r\n", body
  end

  def test_a_merged_note_not_in_its_form_fails_names_the_form_and_writes_nothing
    with_outcome

    result = call("1", "pending", "--kind", "Merged")

    assert_equal [1, OUTCOME], [result.code, body]
    assert_includes result.err, "the Merged line takes the form 'Merged: <branch> into <base> at <commit or pull request>'"
  end

  def test_an_approval_in_its_form_is_written
    with_outcome

    result = call("1", "the owner on 2026-11-24", "--kind", "Approved")

    assert_equal [0, true], [result.code, body.include?("- Approved: the owner on 2026-11-24\n")]
  end

  def test_an_approval_not_in_its_form_fails
    with_outcome

    assert_equal [1, OUTCOME], [call("1", "not yet", "--kind", "Approved").code, body]
  end

  def test_an_abandon_reason_naming_the_superseding_intent_is_written
    with_outcome

    result = call("1", "superseded by intent 12", "--kind", "Abandoned")

    assert_equal [0, true], [result.code, body.include?("- Abandoned: superseded by intent 12\n")]
  end

  def test_an_abandon_reason_saying_why_it_was_dropped_is_written
    with_outcome

    assert_equal 0, call("1", "dropped because the owner chose another tool", "--kind", "Abandoned").code
  end

  def test_an_abandon_reason_in_neither_form_fails_and_names_both
    with_outcome

    result = call("1", "no longer needed", "--kind", "Abandoned")

    assert_equal [1, OUTCOME], [result.code, body]
    assert_includes result.err, "'Abandoned: superseded by intent <id>' or 'Abandoned: dropped because <reason>'"
  end

  def test_a_reverted_line_takes_any_text
    with_outcome

    result = call("1", "nothing delivered", "--kind", "Reverted")

    assert_equal [0, true], [result.code, body.include?("- Reverted: nothing delivered\n")]
  end
end
