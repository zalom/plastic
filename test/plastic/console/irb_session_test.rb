# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/console/irb_session"

# The IRB session of the console.
class ConsoleIrbSessionTest < Minitest::Test
  def test_a_missing_irb_fails_and_says_the_install_left_it_out
    session = Plastic::Console::IrbSession.new(nil, nil)
    session.define_singleton_method(:require) { |_name| raise LoadError }
    error = assert_raises(Plastic::Failed) { session.start }

    assert_equal "plastic console needs irb, which this install left out", error.message
  end
end
