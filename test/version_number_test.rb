# frozen_string_literal: true

require_relative "test_helper"
require "version_number"

class VersionNumberTest < Plastic::TestCase
  def version(text)
    VersionNumber.parse(text)
  end

  def test_parse_drops_a_leading_v_and_any_suffix
    assert_equal "2.0.3", version(" v2.0.3-alpha.4 ").to_s
  end

  def test_a_string_with_no_leading_digits_parses_to_nil
    assert_nil version("latest")
  end

  def test_a_shorter_version_compares_as_if_padded_with_zeros
    assert_equal version("2.0"), version("2.0.0")
  end

  def test_segments_compare_as_numbers_not_text
    assert_operator version("2.10.0"), :>, version("2.9.1")
  end

  def test_a_version_does_not_compare_with_a_string
    assert_nil version("2.0.0") <=> "2.0.0"
  end
end
