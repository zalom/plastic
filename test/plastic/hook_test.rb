# frozen_string_literal: true

require_relative "../test_helper"

class HookTest < Plastic::TestCase
  def test_a_hook_prints_its_reply_as_plain_text
    call = plastic("hook", "echo", input: %({"session_id": "s-1"}))

    assert_equal [0, "session s-1\n"], [call.code, call.out]
    assert_equal "", call.err
  end

  def test_a_hook_with_no_input_reads_an_empty_event
    call = plastic("hook", "echo", input: "  ")

    assert_equal [0, "session \n", ""], [call.code, call.out, call.err]
  end

  def test_a_hook_with_no_reply_prints_nothing
    call = plastic("hook", "quiet")

    assert_equal [0, "", ""], [call.code, call.out, call.err]
  end

  def test_a_broken_event_reads_as_empty_with_one_stderr_line
    call = plastic("hook", "echo", input: "{not json")

    assert_equal [0, "session \n", "plastic hook: the event is not a JSON object; read as empty\n"], [call.code, call.out, call.err]
  end

  def test_a_hook_must_define_respond
    err = StringIO.new
    code = Plastic::Hook.call([], words: "hook", environment: environment(err:))

    assert_equal 0, code
    assert_equal "plastic hook: NoMethodError: Plastic::Hook must define respond\n", err.string
  end
end
