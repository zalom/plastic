# frozen_string_literal: true

# Checks what a person gets from one command call: its exit code, standard
# output and standard error. A String must equal the stream, a Regexp must
# match it, and an Array names parts the stream must include.
module CallAssertions
  def assert_call(call, code:, out: "", err: "")
    assert_equal code, call.code, "exit code"
    assert_stream out, call.out, "standard output"
    assert_stream err, call.err, "standard error"
  end

  private

  def assert_stream(expected, actual, stream)
    return assert_match(expected, actual, stream) if expected.is_a?(Regexp)
    return expected.each { |part| assert_includes actual, part, stream } if expected.is_a?(Array)

    assert_equal expected, actual, stream
  end
end
