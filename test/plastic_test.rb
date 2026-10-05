# frozen_string_literal: true

require_relative "test_helper"

class PlasticTest < Plastic::TestCase
  def test_snake_splits_a_class_name_at_each_capital
    assert_equal "handed_off", Plastic.snake("HandedOff")
  end

  def test_snake_keeps_a_digit_with_its_word
    assert_equal "stage7_build", Plastic.snake("Stage7Build")
  end
end
