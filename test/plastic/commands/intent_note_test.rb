# frozen_string_literal: true

require_relative "../../test_helper"

class IntentNoteTest < Plastic::TestCase
  OUTCOME = "# Outcome\n\nDelivered.\n"
  FILE = "outcome.md"

  def call(*args) = plastic("intent", "note", *args, table: Plastic::CLI::TABLE)

  def body = retrieval.fetch("1", FILE).body

  def revisions = store_graphs.databases.fetch(:knowledge).row("SELECT COUNT(*) AS n FROM document_revisions WHERE path = :path", path: FILE).fetch("n")

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

  def test_the_old_revision_stays_as_a_row
    with_outcome
    before = revisions

    call("1", "all checks pass")

    assert_equal before + 1, revisions
  end

  def test_the_kind_is_kept
    with_outcome

    call("1", "abc123 proves the rows", "--kind", "Commit")

    assert_includes body, "- Commit: abc123 proves the rows\n"
  end

  def test_an_unknown_kind_exits_2_and_writes_nothing
    with_outcome

    result = call("1", "text", "--kind", "Typo")

    assert_equal [2, OUTCOME], [result.code, body]
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

  def test_an_unknown_intent_fails_and_writes_nothing
    result = call("9", "text")

    assert_equal 1, result.code
    assert_empty(result.out.lines.grep(/^files:/))
  end
end
