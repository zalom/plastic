# frozen_string_literal: true

require_relative "../../test_helper"

class EvidenceTextTest < Plastic::TestCase
  def test_extracts_readable_markup_and_rich_text_without_hidden_syntax
    assert_equal "Visible & useful", text.extract("page.html", "<style>hidden</style><p>Visible &amp; useful</p><script>secret</script>")
    assert_equal "Diagram label", text.extract("diagram.svg", "<svg><text>Diagram label</text></svg>")
    assert_equal "Rich text", text.extract("note.rtf", "{\\rtf1\\ansi Rich \\b text}")
  end

  def test_classifies_supported_text_and_reports_unsupported_or_invalid_bytes
    assert_equal :text, text.classify("data.json", "{\"title\":\"Readable\"}")
    assert_equal :unsupported, text.classify("report.pdf", "%PDF-1.7")
    assert_equal :attachment, text.classify("bad.txt", "\xFF".b)
  end

  def test_builds_repeatable_unicode_passages_with_overlap_and_source_lines
    body = "first line\n\n" + ("ž" * 1700) + "\nfinal line\n"

    passages = text.passages(body)

    assert_equal passages, text.passages(body)
    assert passages.all? { |passage| passage.fetch(:body).length <= 1600 }
    assert_equal 2, passages.size
    assert_equal [1, 3], passages.map { |passage| passage.fetch(:line_start) }
    assert_equal 200, passages.first.fetch(:body)[-200..].length
  end

  private

  def text = Plastic::Graph::EvidenceText
end
