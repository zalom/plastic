# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/console/json_value"

# A console value as JSON data.
class ConsoleJsonValueTest < Minitest::Test
  def test_json_values_stay_as_they_are
    assert_equal [1, 1.5, "a", true, false, nil], [1, 1.5, "a", true, false, nil].map { |value| Plastic::Console::JsonValue.of(value) }
  end

  def test_a_float_that_is_not_finite_prints_as_its_inspect_text
    assert_equal ["Infinity", "NaN"], [Float::INFINITY, Float::NAN].map { |value| Plastic::Console::JsonValue.of(value) }
  end

  def test_arrays_and_hashes_convert_their_members_and_hash_keys_become_text
    assert_equal({ "a" => [1, ":b"] }, Plastic::Console::JsonValue.of({ a: [1, :b] }))
  end
end
