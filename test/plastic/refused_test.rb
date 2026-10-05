# frozen_string_literal: true

require_relative "../test_helper"

class RefusedTest < Plastic::TestCase
  def test_the_message_is_the_bare_reason
    assert_equal "the owner holds it", Plastic::Refused.new(:code_a, "the owner holds it").message
  end

  def test_a_refusal_exits_three
    assert_equal 3, Plastic::Refused.new(:code_a, "x").exit_code
  end

  def test_report_raises_the_refusal_the_boundary_prints
    error = assert_raises(Plastic::CLI::Command::Refusal) { Plastic::Refused.new(:code_a, "the owner holds it").report(nil) }

    assert_equal "the owner holds it", error.message
  end
end
