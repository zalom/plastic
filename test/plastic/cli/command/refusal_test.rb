# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandRefusalTest < Plastic::TestCase
  def test_a_refusal_exits_three
    assert_equal 3, Plastic::CLI::Command::Refusal.new("owner").exit_code
  end

  def test_a_refusal_reports_that_the_owner_holds_the_step
    err = StringIO.new
    Plastic::CLI::Command::Refusal.new("owner").report(Plastic::CLI::TextOutput.new(out: StringIO.new, err:))

    assert_equal "plastic: refused, owner", err.string.lines.first.chomp
  end
end
