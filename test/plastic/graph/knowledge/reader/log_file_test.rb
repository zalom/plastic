# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderLogFileTest < Plastic::TestCase
  fixtures :alpha

  LogFile = Plastic::Graph::Knowledge::Reader::LogFile
  Line = Struct.new(:text, :position)

  def test_a_savepoint_adds_only_the_lines_the_log_lacks_after_the_last_position
    file = LogFile.new("kept\n\nnew\n", "1")
    store_database.transaction { |batch| file.savepoint(batch, [Line.new("kept", 4)]) }
    rows = store_database.rows("SELECT position, text FROM work_log WHERE intent_id = '1'").map { |row| [row["position"], row["text"]] }

    assert_includes rows, [5, "new"]
    refute_includes rows.map(&:last), "kept"
  end

  def test_a_savepoint_line_written_with_an_offset_is_stored_in_utc
    file = LogFile.new("2026-10-01T10:00:00+02:00  old line\n", "1")
    store_database.transaction { |batch| file.savepoint(batch, []) }

    assert_equal ["2026-10-01T08:00:00Z"], store_database.rows("SELECT at FROM work_log WHERE intent_id = '1' AND text = 'old line'").map { |row| row["at"] }
  end

  def test_a_work_log_replaces_the_rows_of_the_intent_one_per_line
    file = LogFile.new("- 2026-10-01T10:00:00+02:00 Why n3 s-1 wrote spec.md sha256:#{"a" * 64} Spec\nfree\n", "1")
    store_database.transaction { |batch| file.work_log(batch) }

    assert_equal [1, 2], store_database.rows("SELECT position FROM work_log WHERE intent_id = '1' ORDER BY position").map { |row| row["position"] }
  end
end
