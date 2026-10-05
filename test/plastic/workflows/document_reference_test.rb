# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/document_reference"

class DocumentReferenceTest < Minitest::Test
  def slug(text) = Plastic::Workflows::DocumentReference.new(text).source_slug

  def test_the_store_is_read_from_a_qualified_reference
    assert_equal "plastic", slug("plastic://plastic/411/spec.md")
  end

  def test_a_reference_with_a_revision_names_its_store
    assert_equal "global", slug("plastic://global/1/spec.md?revision=#{"a" * 64}")
  end

  def test_a_reference_without_the_scheme_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { slug("global/1/spec.md") }

    assert_equal 'invalid document reference "global/1/spec.md"', error.message
  end

  def test_a_short_revision_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { slug("plastic://global/1/spec.md?revision=abc") }
  end

  def test_a_path_that_unescapes_to_invalid_text_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { slug("plastic://global/1/%FF.md") }
  end
end
