# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceFitterTest < Minitest::Test
  def test_text_that_still_does_not_fit_is_cut_with_an_ellipsis
    assert_equal "#{"x" * 9}…", CommandReference::Dsl::Fitter.new("x" * 30, 10).to_s
  end

  def test_text_that_fits_is_kept
    assert_equal "short", CommandReference::Dsl::Fitter.new("short", 10).to_s
  end
end
