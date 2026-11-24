# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/child_process"
require_relative "../../../lib/plastic/console/irb_session"

# The IRB session of the console.
class ConsoleIrbSessionTest < Minitest::Test
  SESSION = File.expand_path("../../../lib/plastic/console/irb_session.rb", __dir__)

  def test_a_missing_irb_fails_in_one_line_that_says_where_to_add_it
    session = Plastic::Console::IrbSession.new(nil, nil)
    session.define_singleton_method(:require) { |name| (name == "irb") ? raise(LoadError) : true }
    error = assert_raises(Plastic::Failed) { session.start }

    assert_equal "plastic console needs irb, which this Ruby installation does not have; add it with `gem install irb`", error.message
  end

  def test_the_session_loads_the_irb_of_the_ruby_with_rubygems_off_at_launch
    code = "require #{SESSION.inspect}; Plastic::Console::IrbSession.new(nil, nil).send(:load_irb); print IRB::VERSION"
    out, err, status = ChildProcess.capture3({}, RbConfig.ruby, "--disable-gems", "-e", code)

    assert_equal [0, "", true], [status.exitstatus, err, out.match?(/\A1\.\d+/)]
  end
end
