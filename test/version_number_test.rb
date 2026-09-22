# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../scripts/lib/version_number"

class VersionNumberTest < Minitest::Test
  def test_parse_reads_a_three_segment_version
    assert_equal [4, 0, 3], VersionNumber.parse("4.0.3").segments
  end

  def test_parse_reads_a_single_segment
    assert_equal [18], VersionNumber.parse("18").segments
  end

  def test_parse_drops_a_leading_v
    assert_equal [1, 14, 1], VersionNumber.parse("v1.14.1").segments
  end

  def test_parse_drops_surrounding_space
    assert_equal [3, 3], VersionNumber.parse("  3.3  ").segments
  end

  def test_parse_keeps_only_the_leading_dotted_integers
    assert_equal [2, 0, 0], VersionNumber.parse("2.0.0-alpha.27").segments
  end

  def test_parse_reads_the_version_out_of_a_ruby_banner
    assert_equal [4, 0, 3], VersionNumber.parse("4.0.3p0 (2026-04-21)").segments
  end

  def test_parse_answers_nil_for_an_empty_string
    assert_nil VersionNumber.parse("")
  end

  def test_parse_answers_nil_for_text
    assert_nil VersionNumber.parse("not found")
  end

  def test_parse_answers_nil_for_nil
    assert_nil VersionNumber.parse(nil)
  end

  def test_a_higher_major_is_greater
    assert_operator VersionNumber.parse("4.0.0"), :>, VersionNumber.parse("3.9.9")
  end

  def test_a_higher_patch_is_greater
    assert_operator VersionNumber.parse("3.3.1"), :>, VersionNumber.parse("3.3.0")
  end

  def test_a_shorter_version_is_zero_padded_on_the_left_side
    assert_equal VersionNumber.parse("3.3"), VersionNumber.parse("3.3.0")
  end

  def test_a_shorter_version_is_zero_padded_on_the_right_side
    assert_equal VersionNumber.parse("3.3.0"), VersionNumber.parse("3.3")
  end

  def test_a_shorter_version_is_smaller_when_the_longer_one_has_more
    assert_operator VersionNumber.parse("3.3"), :<, VersionNumber.parse("3.3.1")
  end

  def test_a_longer_version_is_greater_than_its_own_prefix
    assert_operator VersionNumber.parse("3.3.1"), :>, VersionNumber.parse("3.3")
  end

  def test_comparing_with_something_else_answers_nil
    assert_nil VersionNumber.parse("3.3") <=> "3.3"
  end

  def test_comparing_with_something_else_raises_on_an_operator
    assert_raises(ArgumentError) { VersionNumber.parse("3.3") > "3.3" }
  end

  def test_to_s_gives_back_the_dotted_segments
    assert_equal "2.0.0", VersionNumber.parse("2.0.0-alpha.27").to_s
  end
end
