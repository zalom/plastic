# frozen_string_literal: true

require_relative "../test_helper"

class ErrorsTest < Plastic::TestCase
  class Stops < Plastic::CLI::Command
    STOPS = { "usage" => "Usage", "failed" => "Failed", "refused" => "Refused" }.freeze

    argument :kind, label: "KIND", text: "the error to raise"

    def call
      raise Plastic.const_get(STOPS.fetch(parsed[:kind])).new("stopped", next_command: "plastic next", because: "the rule")
    end
  end

  def run_stops(kind)
    out = StringIO.new
    err = StringIO.new
    code = Stops.new([kind], words: "stops", environment: environment(out:, err:)).respond
    [code, out.string, err.string]
  end

  def test_each_error_carries_its_exit_code
    assert_equal [2, 1, 3], [Plastic::Usage, Plastic::Failed, Plastic::Refused].map { |kind| kind.new("x").exit_code }
  end

  def test_each_error_carries_the_next_command_the_reason_and_the_source
    error = Plastic::Failed.new("broke", next_command: "plastic fix", because: "it broke", source: "code_a, step")

    assert_equal ["broke", "plastic fix", "it broke", "code_a, step"], [error.message, error.next_command, error.because, error.source]
  end

  def test_the_reason_is_the_because_line_when_none_is_given
    assert_equal "broke", Plastic::Refused.new("broke").because
  end

  def test_a_failed_error_made_from_a_raised_error_names_its_class
    error = Plastic::Failed.raised(:code_a, "step", ArgumentError.new("bad"))

    assert_equal ["ArgumentError: bad", "code_a, step"], [error.message, error.source]
  end

  def test_a_failed_error_made_from_a_failed_error_keeps_its_message
    error = Plastic::Failed.raised(:code_a, "step", Plastic::Failed.new("bad"))

    assert_equal "bad", error.message
  end

  def test_the_boundary_prints_a_failed_error_with_its_next_and_because_lines
    code, out, err = run_stops("failed")

    assert_equal [1, "plastic: stopped\n", "next: plastic next\nbecause: the rule\n"], [code, err, out]
  end

  def test_the_boundary_prints_a_refused_error_with_its_next_and_because_lines
    code, out, err = run_stops("refused")

    assert_equal [3, true, "next: plastic next\nbecause: the rule\n"], [code, err.start_with?("plastic: refused, stopped\n"), out]
  end

  def test_the_boundary_prints_a_usage_error_with_the_usage_line
    code, _out, err = run_stops("usage")

    assert_equal [2, "plastic: stopped\nplastic stops KIND\n"], [code, err]
  end
end
