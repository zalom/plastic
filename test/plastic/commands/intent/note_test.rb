# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentNoteCaseTest < Plastic::TestCase
  def test_a_note_prints_the_report_and_offers_next
    ran("intent new Alpha")

    assert_case line('intent note 1 "all checks pass"'), code: 0, out: ["report: all checks pass", "next: plastic next"]
  end

  def test_a_note_of_the_commit_kind_prints_the_commit_and_offers_next
    ran("intent new Alpha")

    assert_case line('intent note 1 "abc123 proves it" --kind Commit'), code: 0,
      out: ["commit: abc123 proves it", "next: plastic next"]
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
    assert_equal "#{OUTCOME}\n## Notes\n\n- Report: all checks pass\n", body
  end

  def test_a_second_note_goes_under_the_same_heading
    with_outcome

    call("1", "first")
    call("1", "second")

    assert_equal "#{OUTCOME}\n## Notes\n\n- Report: first\n- Report: second\n", body
  end

  def test_a_note_goes_at_the_end_of_an_existing_notes_section
    with_outcome("# Outcome\n\n## Notes\n\n- Review: earlier\n\n## Verification\n\n- Merged: yes\n")

    call("1", "later")

    assert_equal "# Outcome\n\n## Notes\n\n- Review: earlier\n- Report: later\n\n## Verification\n\n- Merged: yes\n", body
  end

  def test_the_kind_is_kept
    with_outcome

    call("1", "abc123 proves the rows", "--kind", "Commit")

    assert_includes body, "- Commit: abc123 proves the rows\n"
  end

  def test_an_unknown_kind_exits_2_and_writes_nothing
    with_outcome

    result = call("1", "text", "--kind", "Typo")

    assert_equal [2, OUTCOME, true], [result.code, body, result.err.include?("KIND takes Review, Commit, Report")]
  end

  def test_an_outcome_file_edited_by_hand_fails_the_note_and_writes_nothing
    intent = with_outcome
    write("#{intent.dir}/#{FILE}", "#{OUTCOME}\nEdited by hand.\n")
    before = outcome_rows
    result = call("1", "all checks pass")

    assert_equal [1, before, true], [result.code, outcome_rows, result.err.include?("run plastic sync up first")]
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
    assert_equal "# Outcome\n\n## Notes\n\n- Report: first thought\n", body
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

      assert_equal [1, before], [result.code, outcome_rows]
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
