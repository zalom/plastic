# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_text"

class EvidenceTextTest < Plastic::TestCase
  def test_extracts_readable_markup_and_rich_text_without_hidden_syntax
    assert_equal "Visible & useful", text.extract("page.html", "<style>hidden</style><p>Visible &amp; useful</p><script>secret</script>")
    assert_equal "Diagram label", text.extract("diagram.svg", "<svg><text>Diagram label</text></svg>")
    assert_equal "Rich text", text.extract("note.rtf", "{\\rtf1\\ansi Rich \\b text}")
  end

  def test_preserves_boundaries_and_signed_unicode_when_extracting_markup_and_rtf
    assert_markup_boundaries
    assert_rtf_unicode_boundaries
  end

  def test_classifies_supported_text_and_reports_unsupported_or_invalid_bytes
    assert_equal :text, text.classify("data.json", "{\"title\":\"Readable\"}")
    assert_equal :unsupported, text.classify("report.pdf", "%PDF-1.7")
  end

  def test_keeps_invalid_text_bytes_as_an_attachment
    assert_equal :attachment, text.classify("bad.txt", "\xFF".b)
    assert_nil text.extract("bad.txt", "\xFF".b)
  end

  def test_preserves_every_valid_utf8_non_nul_reference_without_an_extension_allowlist
    %w[settings.toml query.sql script.sh main.go task.py README].each do |path|
      assert_equal :text, text.classify(path, "{keep}\\path\n")
    end
  end

  def test_preserves_plain_text_and_decodes_rtf_unicode_and_hex_escapes
    plain = "# Heading\n{json: \\path}\n"

    assert_equal plain, text.extract("note.md", plain)
    assert_equal "žé", text.extract("note.rtf", "{\\rtf1\\ansi\\u382?\\'e9}")
  end

  def test_decodes_a_surrogate_pair_after_an_adjacent_bmp_escape
    source = "{\\rtf1\\ansi\\u382?\\u-10179?\\u-8704?}"

    assert_equal "ž😀", text.extract("note.rtf", source)
  end

  def test_markup_and_rtf_passages_keep_their_original_source_line_ranges
    html = "<html>\n<style>hidden\ncode</style>\n<body>\n<p>First line</p>\n<p>Second &amp; third</p>\n</body>\n</html>"
    rtf = "{\\rtf1\\ansi\nFirst \\b line\\b0\\par\nSecond \\u382? line\n}"

    assert_equal [["First line Second & third", 5, 6]], passage_details(text.extract_with_lines("page.html", html))
    assert_equal [["First line Second ž line", 2, 3]], passage_details(text.extract_with_lines("note.rtf", rtf))
  end

  def test_builds_repeatable_unicode_passages_with_overlap_and_source_lines
    assert_repeatable_passages
    assert_bounded_overlap_and_lines
  end

  private

  def text = Plastic::Graph::EvidenceText
  def unicode_body = "first line\n\n" + ("ž" * 1700) + "\nfinal line\n"
  def passages = text.passages(unicode_body)

  def passage_details(extraction)
    text.passages(extraction).map { |passage| passage.values_at(:body, :line_start, :line_end) }
  end

  def assert_repeatable_passages
    assert_equal passages, text.passages(unicode_body)
    assert_equal 2, passages.size
  end

  def assert_bounded_overlap_and_lines
    assert passages.all? { |passage| passage.fetch(:body).length <= 1600 }
    assert_equal [1, 3], passages.map { |passage| passage.fetch(:line_start) }
    assert_equal 200, passages.first.fetch(:body)[-200..].length
  end

  def assert_markup_boundaries
    assert_equal "first second", text.extract("page.html", "<p>first</p><p>second</p>")
    assert_equal "first second", text.extract("diagram.svg", "<text>first</text><text>second</text>")
  end

  def assert_rtf_unicode_boundaries
    assert_equal "\uFF37", text.extract("note.rtf", "{\\rtf1\\ansi\\u-201?}")
    assert_equal "😀", text.extract("note.rtf", "{\\rtf1\\ansi\\u-10179?\\u-8704?}")
    assert_equal "žć", text.extract("note.rtf", "{\\rtf1\\ansi\\u382?\\u263?}")
  end
end
