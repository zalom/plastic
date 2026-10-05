# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/intent_id_format"

class IntentIdFormatTest < Minitest::Test
  def validate(id) = Plastic::Workflows::IntentIdFormat.validate(id)

  def test_digits_followed_by_letters_pass
    assert_nil validate("402a")
  end

  def test_an_id_that_starts_with_a_letter_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { validate("a402") }

    assert_equal 'invalid intent id "a402"', error.message
  end

  def test_an_id_with_capitals_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { validate("402A") }
  end
end
