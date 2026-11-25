# frozen_string_literal: true

require_relative "../test_helper"
require "plastic/inflector"

class InflectorTest < Plastic::TestCase
  def test_underscore_splits_a_class_name_at_each_capital
    assert_equal "handed_off", Plastic::Inflector.underscore("HandedOff")
  end

  def test_underscore_keeps_a_digit_with_its_word
    assert_equal "stage7_build", Plastic::Inflector.underscore("Stage7Build")
  end
end
