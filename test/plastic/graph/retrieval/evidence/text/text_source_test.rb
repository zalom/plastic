# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextTextSourceTest < Plastic::TestCase
  def source(path, bytes) = Plastic::Graph::Retrieval::Evidence::Text::TextSource.new(path, bytes)

  def test_valid_utf8_text_is_text
    assert_equal :text, source("notes", "plain").classify
  end

  def test_bytes_with_a_nul_are_an_attachment
    assert_equal :attachment, source("notes.txt", "a\0b").classify
  end

  def test_invalid_utf8_is_an_attachment
    assert_equal :attachment, source("notes.txt", "\xFF".b).classify
  end

  def test_a_readable_pdf_is_unsupported
    assert_equal :unsupported, source("Report.PDF", "%PDF").classify
  end

  def test_an_uppercase_markup_extension_strips_tags
    assert_equal "Shown", source("page.HTML", "<b>Shown</b>").extract
  end

  def test_an_rtf_file_decodes_its_control_words
    assert_equal "Rich", source("note.rtf", "{\\rtf1 Rich}").extract
  end

  def test_anything_not_text_extracts_nothing
    assert_nil source("report.pdf", "%PDF").extract_with_lines
  end
end
