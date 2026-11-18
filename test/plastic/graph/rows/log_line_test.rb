# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/rows/log_line"

class WorkLogLineTest < Plastic::TestCase
  LogLine = Plastic::Graph::Work::LogLine
  AT = "2026-11-16T15:02:11Z"
  SHA = "a" * 64

  def row(**fields) = LogLine.new(intent_id: "1", position: 1, at: AT, phase: "", node: "", session_id: nil, kind: "noted", path: "", sha256: "", text: "", origin_id: "o", **fields)

  def test_a_line_prints_the_full_hash_and_a_dash_for_every_empty_field
    line = row(phase: "Why", node: "n3", session_id: "auto-a1b2", kind: "wrote", path: "spec.md", sha256: SHA)

    assert_equal "- #{AT} Why n3 auto-a1b2 wrote spec.md sha256:#{SHA}", line.line
    assert_equal "- #{AT} - - - noted - - Spec written", row(text: "Spec written").line
  end

  def test_a_printed_line_reads_back_into_the_same_fields
    line = row(phase: "Why", node: "n3", session_id: "auto-a1b2", kind: "wrote", path: "spec.md", sha256: SHA, text: "the new why")

    assert_equal line.to_h.slice(:at, :phase, :node, :session_id, :kind, :path, :sha256, :text), LogLine.parse(line.line).to_h
  end

  def test_a_line_with_no_time_prints_a_dash_and_reads_back_with_no_time
    assert_nil LogLine.parse(row(at: nil, text: "free").line).fetch(:at)
  end

  def test_a_line_that_does_not_parse_becomes_a_noted_row_with_its_text
    parsed = LogLine.parse("2026-10-01T10:00:00+02:00  an old savepoint line")

    assert_equal ["noted", "2026-10-01T10:00:00+02:00  an old savepoint line", nil], parsed.values_at(:kind, :text, :at)
  end

  def test_a_noted_row_made_from_a_loose_line_prints_a_line_that_parses
    printed = row(at: nil, text: "loose words").line

    assert_equal "loose words", LogLine.parse(printed).fetch(:text)
  end
end
