# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandFailureTest < Plastic::TestCase
  def test_a_failure_exits_one
    assert_equal 1, Plastic::CLI::Command::Failure.new("it broke").exit_code
  end

  def test_a_failure_reports_its_message_on_the_error_stream
    err = StringIO.new
    Plastic::CLI::Command::Failure.new("it broke").report(Plastic::CLI::TextOutput.new(out: StringIO.new, err:))

    assert_equal "plastic: it broke\n", err.string
  end
end
